# initialization, allign, constexpr

## Статическая и динамическая инициализация

```c++
int a = 42;
int f() {
    int result;
    std::cin >> result;
    return result;
}

int a = 42; // инициализируется в момент компиляции
int b = f(); // инициализируется
```

`a` инициализируется на этапе компиляции, под `b` просто резевируются 4 байта, а её инициализация происходит в момент старта программы. 

В C++ все функции по дефолту исполняются в рантайме, но иногда мы хотим получить значение на этапе компиляции. Это можно сделать таким костылём?

```c++
template <size_t a, size_t b>
struct max {
    static size_t const value = a < b ? b : a;
}

template <typename A, typename B>
struct variant {
    char stg[max<sizeof(A), sizeof(B)>::value];
}

```

В C++11 разрешили делать функции, которые выполняются в компайл-тайме:

```c++
template <typename T>
constexpr T const& max(T const& a, T const& b) {
    return a < b ? b : a;
}
```

Если функция `constexpr`, то она должна внутри вызывать только `constexpr` функции.

С появлением `constexpr` функций обнаружилась нужда, например, в `constexpr` переменных. При этом константные переменные со статической инициализацией могут использоваться в компайл-тайме.

// TODO



## if constexpr

Вернёмся к реализациию [function](https://github.com/sorokin/function).

В его имплементации использовался класс `type_descriptor` со SFINAE. Нам повезло, что критерий для объекта был только один (`fits_small_storage`), если бы их было несколько, то это выглядело бы сильно хуже. Но даже в нашем случае это выглядит громоздко, например, мы  заводим функцию `initialize_storage`, которая используется только один раз.

Мы могли бы сделать это через `if`, но так получится не всегда:

```c++
struct mytype1 {
    static constexpr bool has_foo = true;
    void foo();
};

struct mytype2 {
    static constexpr bool has_foo = false;
    void bar();
};

template <typename T>
void f(T obj) {
    if (T::has_foo) {
        obj.foo();
    } else {
        obj.bar();
    }
}
```

Дело в том, что при компиляции `if` оставляет обе ветки, но одна из них не скомпилируется, если у объекта нет какой-то из функций.

В языке для этого появилась конструкция `if constexpr`. Тогда код будет выглядеть следующим образом:

```c++
template <typename T>
void f(T obj) {
    if constexpr (T::has_foo) {
        obj.foo();
    } else {
        obj.bar();
    }
}
```

`if constexpr` работает следующим образом: он требует, чтобы условие было `constexpr` выражением и делает бранчинг на этапе компиляции, не подставляя ту ветку, которая не подходит условию.