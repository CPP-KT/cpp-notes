# Perfect forwarding
- [Запись лекции №1](https://youtu.be/M9h0_xBM7_8?t=1786)
- [Запись лекции №2](https://www.youtube.com/watch?v=ydQD7-XSSt4)
---
Когда мы говорили про `shared_ptr`, у нас была функция `make_shared`, которая принимала какие-то аргументы и передавала их в конструктор. 

Посмотрим на возможные реализацию такой функции (для упрощения на примере одного параметра):

```c++
template<typename T>
void g1(T a){
    f(a);
}
template<typename T>
void g2(T const& a){
    f(a);
}
template<typename T>
void g3(T& a){
    f(a);
}
```

Все 3 случая не подходят:

- Принимать по значению неприятно, если объект дорого копировать
- Принимать по `const&` не получится, если на самом деле функция `f` принимает ссылку
- Принимать по `&` нельзя, так как она не биндится к `rvalue`

Можно было бы сделать перегрузку с `&` и `const&`, но тогда нужно 2^n перегрузок для n параметров, что не очень удобно.

**Perfect forwarding** - принять аргументы и передать их куда-то с теми свойствами, с которыми они пришли (rvalue/lvalue, cv). В C++11 есть специальный механизм для решения этой проблемы. Чтобы понять, как оно работает, нужно познакомиться с правилами вывода ссылок в C++11.

## Reference collapsing rule

В C++ нельзя сделать ссылку на ссылку, поэтому ссылки схлопываются (коллапсятся):

```c++
typedef int& mytype1;
typedef mytype1& mytype2;
static_assert(std::is_same_v<mytype2, mytype1>); // true

template <typename T>
void foo(T&);

int main() {
    foo<int&>(); // void foo(int&)
}
```

Это было в языке всегда с момента появления ссылок. Когда появились rvalue ссылки, правила схлопывания ссылок доопределили:

```plain
& & -> &
& && -> &
&& & -> &
&& && -> &&
```

## Universal reference

Чтобы сделать perfect forwarding, нужно как-то запомнить, передавалось в шаблон rvalue или lvalue. В C++11 правила вывода шаблонных параметров были определены специальным образом, который позволяет сохранить эту информацию:

```c++
template <typename T>
void g(T&& a) {
    f(a);
}

int main {
    g(42); // rvalue: T -> int, void g(int&&)
    int a;
    g(a); // lvalue: T -> int&, void g(int&)
}
```

Такие ссылки (шаблонный параметр + rvalue-ссылка) называются *универсальными*. 

## std::forward

Как передавать параметр дальше? Внутри тела функции параметр это именованная переменная, поэтому она lvalue (ситуация очень похожа на то, как вводили `std::move`).  Для этого передачи параметра так, как он пришёл, существует `std::forward`. 

Можно сделать так:

```c++
template <typename T>
void g(T&& a) {
    f(static_cast<T&&>(a));
}

int main {
    g(42); // rvalue: T -> int, void g(int&&), f(static_cast<int&&>(a))
    int a;
    g(a); // lvalue: T -> int&, void g(int&), f(static_cst<int&>(a))
}
```
Библиотечная функция написана примерно так:

```c++
template<typename T>
T&& forward(T& obj) {
    return static_cast<T&&>(obj);
}

template <typename T>
void g(T&& a) {
    f(forward<T>(a));
}
```

Такой `forward` может быть не очень хорошим по той причине, что если забыть написать тип явно в вызове, то он будет выводится и может вывестись не так, как нам надо (в случае перегрузки для rvalue-ссылки `T&&` может выводиться `T -> int&`) *TODO: Если знаете, когда неверно выводится для перегрузки `T&`, напишите.*

Это фиксится следующим образом:

```c++
template <typename T>
struct type_identity {
    typedef T type;
};

template <typename T>
T&& forward(typename type_identity<T>::type& obj) {
    return static_cast<T&&>(obj);
}
```

В STL вместо `type_identity` используется `remove_reference`. Так же есть перегрузка для rvalue (`T&&`), которая полезна, например, для форварда значения, возвращаемого функцией.

## Variadic templates

Осталось понять, как делать функцию, принимающую произвольное число шаблонных параметров. Для этого в C++ сделали специальный синтаксис variadic шаблонов:

```c++
template <typename... T>
void g(T&& ...args) {
    f(std::forward<T>(args)...);
}
```

Можно думать, что `...` пишутся там, где обычно аргументы перечисляются через запятую.

Проще всего понять, как они работают, на примерах:

```c++
template <typename... U>
struct tuple {};

void g(int, float, char);

struct agg {
    int a;
    float b;
    char c;
}

template <typename... V>
void f(V... args) {
    tuple<V...> t;
    g(args...);
    agg a = {args...};
}

int main() {
    f<int, float, char>(1, 1.f, '1');
}
```

Так же можно использовать variadic в перечислении базовых классов:

```c++
template <typename... U>
struct tuple : U... {
    using U::foo...;
};
```

Как это работает в общем случае? `...` показывают, на каком уровне нужно раскрыть аргументы.

```c++
template <typename... V>
struct tuple {};

template <typename... V2>
struct tuple2 {};

template <typename... V>
void f(V... args) {  // void f(int arg0, float arg1, char arg2);
    tuple<tuple2<V...>> t1;  // tuple<tuple2<int, float, char>>
    tuple<tuple2<V>...> t2;  // tuple<tuple2<int>, tuple2<float>, tuple2<char>>
}

template <typename... U>
void g(U&&... args) {
    f(std::forward<U>(args)...);  // раскрываются в f, forward от каждого
}
```

Можно раскрывать одновременно два variadic'a одинакового размера (или один с самим собой):

```c++
template <typename... V>
void f(V... args) {  // void f(int arg0, float arg1, char arg2);
    tuple<tuple2<V, V>...> t3;  // tuple<tuple2<int, int>, tuple2<float, float>, tuple2<char, char>>
}
```

Если `...` несколько, то раскрываются сначала внутренние:

```c++
template <typename... V>
void f(V... args) {  // void f(int arg0, float arg1, char arg2);
    tuple<tuple2<V, V...>...> t4; 
    // tuple<tuple 2<int, int, float, char>,
    //       tuple2<float, int, float, char>,
    //       tuple2<char, int, float, char>>
}
```

Как передавать два пака шаблонов? Для классов так делать нельзя, для них пак параметров должен быть последним в списке.

```c++
template <typename... U, typename... V> // COMPILE ERROR
struct x {}; 

template <typename... U, typename V> // COMPILE ERROR
struct y{}; 

template <typename U, typename... V> // OK
struct t {}; 
```

Это важно только для primary шаблона, для partial специализаций нет, так как они выводятся, а не указываются явно:

```c++
template <typename... UArgs, typename... VArgs>
struct x<tuple<UArgs...>, tuple<VArgs...>>
{};

int main() {
    x<tuple<int, float>, tuple<double, char>> xx;
}
```

Для функций шаблонные параметры тоже могут выводиться,  поэтому для функций нет ограничений на то, что пак должен быть последним.

```c++
template <typename... U, typename... V>
void h(tuple<U...>, tuple<V...>) {
    tuple<tuple2<U, V>...> t3;
}
```

### Несколько примеров применения

```c++
template <typename T, typename... Args>
std::unique_ptr<T> make_unique(Args&& ...args) {
    return std::unique_ptr<T>(new T(std::forward<Args>(args)...));
}
```

Так же реализован `make_shared` для`std::shared_ptr` и `emplace_back` для `std::vector`

```c++
template <typename... Ts>
void write() {}

template <typename T0, typename... Ts>
void write(T0 const& arg0, Ts const& ...args) {
    std::cout << arg0;
    write(args...);
}
```
