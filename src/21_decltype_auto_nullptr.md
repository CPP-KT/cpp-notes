 # Perfect backwarding.
- [Запись лекции №1](https://www.youtube.com/watch?v=ydQD7-XSSt4)

---

Помните [perfect forwarding](./20_perfect_forwarding.md)? Там мы учились передавать в функцию аргументы. Теперь ситуация страшнее: perfect backwarding — надо ещё значение вернуть:

```c++
template <typename... Args>
??? g(Args&&... args) {
    return f(std::forward<Args>(args)...);
}
```

## `decltype`.

В C++11 появилась конструкция, которая позволяет по выражению узнать его тип:

```c++
int main() {
    decltype(2 + 2) a = 42; // int a = 42;
}
```

При этом `decltype` сохраняет все ссылки и все `const`'ы:

```c++
int foo();
int& bar();
int&& baz();

int main() {
    decltype(foo()) x; // prvalue   int x;
    decltype(bar()) x; // lvalue    int& x;
    decltype(baz()) x; // xvalue    int&& x;
}
```

На самом деле существует по сути два `decltype`: для выражений и для имён. То есть мы можем сделать что-то такое:
```c++
struct mytype {
    int nested;
};
decltype(mytype::nested) a;
```

`mytype::nested` — некорректное выражение, но брать от него `decltype` можно.\
Или вот, более показательный пример:

```c++
int a;
decltype(a) b;   // int b, так как от переменной.
decltype((a)) c; // int& c, так как от выражения, а оно lvalue.
```

И отсюда уже понятнее, как писать perfect backwarding:

```c++
template <typename... Args>
decltype(f(std::forward<Args>(args)...)) g(Args&&... args) {
    return f(std::forward<Args>(args)...);
}
```

Блин, это не компилируется(\
Потому что компилятор видит `args` позже, чем возвращаемое значение. Что же делать?..

## `std::declval`.

Нам надо породить значение из ничего. Это вообще конструктор по умолчанию называется, но закладываться на то, что у каждого типа из `Args` есть таковой.

Поэтому чтобы породить значение из ниоткуда честно, в стандартной библиотеке есть функция `std::declval`.

```c++
template <typename... Args>
decltype(f(std::forward<Args>(std::declval<Args>())...)) g(Args&&... args) {
    return f(std::forward<Args>(args)...);
}
```

При этом сама функция `std::declval` обычно не имеет тела, чтобы никакой дурак не вздумал её вызвать. Вы можете её использовать только там, где не происходит вычисление. Это называется *unevaluated context* (другими его примерами, помимо `decltype`, являются `sizeof` или `alignof`).

Сигнатура у `declval` могла бы выглядеть как-то так:

```C++
template <typename T>
T declval();
```

Но при использовании такой сигнатуры, могут возникать проблемы с неполными типами (просто не скомпилируется). Это происходит из-за того, что если функция возвращает структуру, то в точке, где вызывается эта функция, эта структура должна быть complete типом. Чтобы обойти это, делают возвращаемый тип rvalue-ссылкой:

```c++
template <typename T>
T&& declval();
```

## Trailing return type.

Чтобы не писать `declval`, сделали возможной следующую конструкцию:

```c++
template <typename... Args>
auto g(Args&&... args)
        -> decltype(f(std::forward<Args>(args)...)) {
    return f(std::forward<Args>(args)...);
}
```

Trailing return type применяется также вот в таком ключе:

```c++
struct foobar {
    using type = int;

    type f();
    void g(type);
};
```

Пусть мы хотим реализовать функции вне класса. Можем ли мы написать так:

```c++
void foobar::f(type) { /* ... */ }
```

Можем. А так?

```c++
type foobar::g() { /* ... */ }
```

А так не можем, потому что `type` мы видим раньше, нежели `foobar::`. Поэтому можно сделать trailing return type:

```c++
auto foobar::f() -> type { /* ... */ }
```

Желающие могут почитать про [unqualified name lookup](https://en.cppreference.com/w/cpp/language/unqualified_lookup), где подробно написано, почему в этом примере `type` найдётся, а в предыдущем — нет.

## `decltype(auto)`.

Очень громоздко получается, когда мы пишем в `decltype` то же, что и в `return`. Давайте не надо:

```c++
int main() {
    decltype(auto) b = 2 + 2;
    // Эквивалентно
    decltype(2 + 2) b = 2 + 2;
}

template <typename... Args>
decltype(auto) g(Args&& ...args) {
    return f(std::forward<Args>(args)...);
}
// Эквивалентно тому, что мы уже писали с trailing return type.
```

## `auto`.

Ещё есть такая штука как просто `auto`. Это тоже способ вывести тип переменной/возвращаемого значения автоматически, но другой.

Правило вывода типов у `auto` почти полностью совпадают с тем, как выводятся шаблонные параметры. Поэтому `auto` отбрасывает ссылки, `const` и `volatile`.

```c++
int& bar();

int main() {
    auto c = bar(); // int c = bar()
    auto& c = bar(); // int& c = bar()
}
```

Мораль: `auto` бывает нужен довольно редко, чаще `decltype(auto)`.

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

## `nullptr`.

До C++11 для нулевого указателя использовалось либо `0`, либо макрос `NULL` (который в C++ просто равен `0`). Правило было такое: числовая константа, которая **на этапе компиляции** вычисляется в `0`, может приводиться неявно в нулевой указатель.

Это привело бы к проблеме при использовании forwarding'а: `std::forward<int>(0)` — ни в каком месте не compile-time константа, равная нулю.

В C++11 появился отдельный тип `nullptr_t`, который может приводиться к любому указателю. Определено это примерно так:

```c++
struct nullptr_t {
    template <typename T>
    operator T*() const {
        return 0;
    }
}
nullptr_t const nullptr;
```

Единственное отличие в том, что в C++11 `nullptr` это keyword, встроенный в язык, а не глобальная переменная. Но к типу всё ещё можно обратиться через `decltype(nullptr)`, в стандартной библиотеке есть `std::nullptr_t`, который так и определён.

