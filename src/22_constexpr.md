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