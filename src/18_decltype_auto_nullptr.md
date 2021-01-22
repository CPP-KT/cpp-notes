 # Decltype, declval, auto, nullptr
- [Запись лекции №1](https://www.youtube.com/watch?v=ydQD7-XSSt4)
---
## decltype

Иногда возвращаемый тип не хочется писать руками.

```c++
int f();
??? g() {
    return f()
}
```

В C++11 появилась конструкция, которая позволяет по выражению узнать его тип:

```c++
int main() {
    decltype(2 + 2) a = 42; // int a = 42;
}

decltype(f()) g() {
    return f();
}
```

`decltype `сделан так, чтобы его было удобно использовать для возврата значений:

```c++
int foo();
int& bar();
int&& baz();
// decltype(foo()) int
// decltype(bar()) int&
// decltype(baz()) int&&

// decltype(expr)
// type для (prvalue)
// type& для (lvalue)
// type&& для (xvalue)
```

О `decltype` можно думать как о двух языковых конструкциях в одном синтаксисе

```c++
// decltype (expr) - работает, как написано выше
// decltype (var_name) - возвращает тип этой переменной
```

`decltype` определён таким образом, что он работает и для членов класса:

```c++
struct x {
    int a;
};

int main() {
    x::a; // COMPILE ERROR
    decltype(x::a);
    
    int a;
    decltype(a) b = 42; // int b = 42
    decltype((a)) c = a; // int& c = a
}
```

Последнее работает так, потому что `(a)` это выражение и оно имеет тип `int&`, а `a` - это имя переменной.

## declval

Иногда хочется узнать тип чего-то, что зависит от шаблонных аргументов функции, но просто сделать это с помощью `decltype` не получится, так как тогда компилятор встречает обращение к параметру функции, когда ещё не дошёл до его объявления.  

Для этого есть синтаксическая конструкция `declval`:

```c++
int foo(int);
float foo(float);

template <typename Arg0>
decltype(foo(arg0)) qux(Arg0&& arg0) { // COMPILE ERROR
    return foo(std::forward<Arg0>(arg0));
}

template <typename Arg0>
decltype(foo(declval<Arg0>())) qux(Arg0&& arg0) {
    return foo(std::forward<Arg0>(arg0));
}
```

Сигнатура у `declval` могла бы выглядеть как-то так:

```C++
template <typename T>
T declval();
```

Для `declval` не нужно тело функции, так как `decltype` не генерирует машинный код и считается на этапе компиляции.

В языке есть несколько мест с похожей логикой - например, `sizeof`. Такие места называются *unevaluated contexts*.

При использовании сигнатуры, как выше, могут возникать проблемы с неполными типами (просто не скомпилируется). Это происходит из-за того, что если функция возвращает структуру, то в точке, где вызывается эта функция, эта структура должна быть complete типом. Чтобы обойти это, делают возвращаемый тип rvalue-ссылкой:

```c++
template <typename T>
T&& declval();
```

## Trailing return types

Чтобы не писать `declval`, сделали возможной следующую конструкцию:

```c++
template <typename Args>
auto qux(Args&& ...args) -> decltype(foo(std::forward<Args>(args)...)) {
    return foo(std::forward<Args>(args)...);
}
```

## auto

Можно заметить, что в `return` и `decltype` повторяется одно и то же выражение. Для этого добавили возможность писать `decltype(auto)`:

```c++
int main() {
    decltype(auto) b = 2 + 2; // int b = 2 + 2
}

template <typename Args>
decltype(auto) qux(Args&& ...args) {
    return foo(std::forward<Args>(args)...);
}
```

Возникает вопрос, а зачем там вообще `decltype`, можно ли его заменить на просто `auto`? Для этого стоит сказать о том, как работает `auto`.

Правило вывода типов у `auto` почти полностью совпадают с тем, как выводятся шаблонные параметры. Поэтому `auto` отбрасывает ссылки и `cv`.

```c++
int& bar();

int main() {
    auto c = bar(); // int c = bar()
    auto& c = bar(); // int& c = bar()
}
```

Поэтому обычный `auto` в возвращаемом типе отбрасывает ссылки с `cv`, поэтому чаще всего нам нужно `decltype(auto)`.

И ещё стоит сказать, что если у функции несколько `return`'ов, которые выводятся в разные типы, то использовать `decltype` и `auto` нельзя:

```c++
auto f(bool flag) { // COMPILE ERROR
    if (flag) {
        return 1;
    } else {
        return 1u;
    }
}
```

## nullptr

До C++11 для нулевого указателя использовалось либо 0, либо макрос `NULL`. Правило было такое - числовая константа, которая вычисляется в 0, может приводиться неявно в нулевой указатель.

Это привело бы к проблеме при использовании форвардинга, так как тип бы выводился в `int`.

В C++11 появился отдельный тип `nullptr_t`, который может приводиться к любому указателю. Определено это примерно так:

```c++
struct nullptr_t {
    template <typename T>
    opeartor T*() const {
        return 0;
    }
}
nullptr_t const nullptr;
```

Единственное отличие в том, что в C++11 `nullptr` это keyword, встроенный в язык, а не глобальная переменная. Но к типу всё ещё можно обратиться через `decltype(nullptr)`, в стандартной библиотеке есть `std::nullptr_t`, который так и определён.

