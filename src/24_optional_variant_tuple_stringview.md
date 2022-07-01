# optional, variant, tuple, string_view

- [Запись лекции №1](https://www.youtube.com/watch?v=bJl0xlPdPj0)
- [Запись лекции №2](https://www.youtube.com/watch?v=NAA0z66IEvE)
- [Запись лекции №3](https://www.youtube.com/watch?v=hrUtXP1sZXk)
- [Запись лекции №4](https://www.youtube.com/watch?v=Dp2AIvae27M)

## optional

 ### Пример:

```c++
struct deferred_value {
	int compute_value() const;
	int get_value() const {
    	if (!is_initialized) {
        	cached_value = compute_value();
        	is_initialized = true;
        }
        return cached_value;
	}
  private:
    mutable bool is_initialized = false;
    mutable int cached_value;
};
```

Проблема такого кода - две переменных, связь которых не очень очевидна, если они будут в составе -нибудь большого класса. Если это не очевидно для компилятора, то будет плохо оптимизациям.

Можно сделать так:

```c++
template <typename T>
struct deferred_value {
	T compute_value() const;
	T get_value() const {
    	if (!cached_value) {
        	cached_value = std::make_unique<T>(compute_value());
        }
        return *cached_value;
	}
  private:
    mutable std::unique_ptr<T> cached_value;
};
```

Вместо двух переменных одна, ожидаем, что `cached_value` может быть нулевым. Но теперь получили динамическую аллокацию.

### Реализация optional:

```c++
template <typename T>
struct optional {
    optional() : is_initialized(false) {}
    optional(T value) : is_initialized(true) {
        new(&storage) T(std::move(value));
    }
    ~optional {
        if (is_initialized) {
            retinterpret_cast<T&>(storage).~T();
        }
    }
  private:
    bool is_initialized;
    std::aligned_storage_t<sizeof(T), aligonf(T)> storage;
};
```

Такой класс есть в стандартной библиотеке и называется `std::optional`.

В стандартной библиотеке у `optional` есть конструктор и метод `emplace`, создающие объект уже внутри `optional` (полезно, если объект дорого копировать и перемещать).

```c++
template<class... Args>
constexpr explicit optional( std::in_place_t, Args&&... args );
// std::optional<std::string> o5(std::in_place, 3, 'A');
```

У него есть дополнительный аргумент `std::inplace_t`, который нужен, чтобы различать, передают аргументы для конструктора объекта `T` или просто для `optional`.

Разыменование пустого `optional` это UB, но метод `value` бросает исключение.

Проблема наивной реализации `optional` в том, что она не сохраняет тривиальности класса `T`. Например, если класс `T` имеет пустой деструктор (`is_trivially_destructible<T>`), то хотелось бы, чтобы и `optional `имел такой деструктор.

Реализовать это через *SFINAE* не получится, так как у деструктора нет аргументов. Можно сделать базовый класс:

```c++
template <typename T>
struct optional_storage {
    bool is_initialized;
    std::aligned_storage_t<sizeof(T), aligonf(T)> storage;
};

template <typename T, bool TriviallyDestructible>
struct optional_base : optional_storage<T> {
    ~optional_base() {
        if (this->is_initialized) {
            retinterpret_cast<T&>(this->storage).~T();
        }
    }
};

template <typename T>
struct optional_base<T, true> : optional_storage<T> {
    ~optional_base() = default,
};

template <typename T>
struct optional: optional_base<T, std::is_trivially_destructible<T>> {  
    // ...
};
```

Примерно так это и реализовано в стандартной библиотеке, хоть и получается, что на каждую тривиальность нужно заводить по базовому классу.

## variant

Предположим, что мы хотим хранить в `deffered_value` либо посчитанное значение, либо функцию, которая может его посчитать. Когда значение уже посчитано, хранить функцию нам не нужно. Такое можно было бы оптимизировать с помощью `union`. Для этого в стандартной библиотеке уже есть класс `std::variant`. 

```c++
int main() {
    std::variant<A, B, C> v;
}
```

Тогда реализация выглядела бы так:

```c++
template <typename compute_func_t, T>
struct deffered_value {
  T get() const {
      if (compute_func_t* f = std::get_if<compute_func_t>(&state)) {
          state = (*f)();
      }
      return std::get<T>(state);
  }
  private:
    mutable std::variant<compute_func_t, T> state;
}
```

Проблемное место `variant` - это то, как к нему обращаться. Все способы имеют свои проблемы.

В `std::variant` можно обращать как по индексу (`std::get<1>`), так и по типу (`std::get<T>`). Если несколько типов одинаковые, то идентификация по типу не скомпилируется.

`std::get_if<T>` возвращает нулевой указатель, если альтернатива не совпадает, иначе указатель на объект типа `T`, лежащий в `variant`.

Интерфейс такого обращения не позволяет проверить, что рассмотрены все альтернативы. Чтобы получать в таком случае ошибку компиляции, у `variant` есть специальный  механизм.

### Паттерн visitor

Представим такую ситуацию:

```c++
struct base {
    virtual void foo() = 0;
    virtual ~base() = default;
};
struct derived1 : base {};
struct derived2 : base {};
struct derived3 : base {};
void foo(base& b) {
    b.foo();
}
```

Функций вида `foo` может быть очень много, при этом каждая из них не очень осмысленная. Чтобы избежать такой ситуации, используется паттерн *visitor*. 

```c++
struct base_visitor {
    virtual void visit(derived1&) = 0;
    virtual void visit(derived2&) = 0;
    virtual void visit(derived3&) = 0;
  protected:
    ~base_visitor() = default;
};

struct foo_visitor final : base_visitor {
    void visit(derived1&) {}
    void visit(derived2&) {}
    void visit(derived3&) {}
};

struct base {
    virtual void accept(base_visitor& v) = 0;
    virtual ~base() = default;
};

struct derived1 : base {
    void accept(base_visitor& v) {
        v.visit(*this);
    }
};

struct derived2 : base {
    void accept(base_visitor& v) {
        v.visit(*this);
    }
};

struct derived3 : base {
    void accept(base_visitor& v) {
        v.visit(*this);
    }
};

void foo(base& b) {
    foo_visitor v;
    b.accept(v);
}
```

Это лучше тем, что если появится ещё один класс `derived4`, то нужно будет добавить функцию в `visitor`, не меняя интерфейс класса (особенно это важно, если его изменение недосупно). 

Пример использования в реальной жизни - обход АСТ (абстрактного синтаксического дерева), не меняя интерфейс его узлов.

Возвращаясь к `variant`: для `std::variant` есть `std::visit`

```c++
template <typename compute_func_t, T>
struct deffered_value {
	struct state_visitor {
        void operator()(compute_func_t const& compute) {}
        void operator()(T const& val) {}
    }
	T get() const {
        std::visit(state_visitor(), state);
	}
  private:
    mutable std::variant<compute_func_t, T> state;
}
```

Это не очень удобно, так как приходится создавать новый класс. Можно ли сделать это с помощью лямбды? К сожалению, у них нет перегрузок, но это можно реализовать отдельно:

```c++
template <typename A, typename B> // A, B - любые функторы или лямбды
struct overloaded : A, B {
    using A::operator();
    using B::operator();
}
```

Это называют *overload pattern*, который в общем случае выглядит как-то так:

```c++
struct overloaded;

template <typename Func0>
struct overloaded<Func0> : std::remove_reference_t<Func0> {
    overloaded(Func0&& func0)
        : Func0(std::forward<Func0>(func0)) {}
    using std::remove_reference_t<Func0>::operator();
};

template <typename Func0, typename... Funcs>
struct overloaded<Func0, Funcs...> : std::remove_reference_t<Func0>, overloaded<Funcs...> {
    overloaded(Func0&& func0, Funcs&&... funcs)
        : Func0(std::forward<Func0>(func0)),
    	  overloaded<Funcs...>(std::forward<Funcs>(funcs)...) {}
    using std::remove_reference_t<Func0>::operator();
    using overloaded<Funcs...>::operator();
}

template <typename... Funcs>
overloaded<Funcs...> overload(Funcs&&... funcs) {
    return overloaded<Funcs...>(std::forward<Funcs>(funcs)...);
}
```

Про `std::visit` и *overload pattern* есть интересная статья ["std::visit is everything wrong with modern C++"](https://bitbashing.io/std-visit.html).

На [cppreference](https://en.cppreference.com/w/cpp/language/using_declaration) приведён пример такого `Overloader`:

```c++
template <typename... Ts>
struct Overloader : Ts... {
    using Ts::operator()...; // exposes operator() from every base
};
 
template <typename... 	T>
Overloader(T...) -> Overloader<T...>; // C++17 deduction guide, not needed in C++20
// нужно, чтобы выводились шаблонные параметры класса

int main() {
    auto o = Overloader{ [] (auto const& a) {std::cout << a;},
                         [] (float f) {std::cout << std::setprecision(3) << f;} };
}
```

*Note*: такой `Overloader` является [aggregate](https://en.cppreference.com/w/cpp/language/aggregate_initialization), поэтому ему можно не писать конструктор и инициализировать базовые классы через `{}`.

### variant и исключения

Если все альтернативы `variant`тривиально-копируемые, то он копируется просто побайтово.

```c++
using type = std::variant<int, char, double>;
void copy (type& a, type const& b) {
    a = b;
}
```

Иначе в копировании будет происходить switch по альтернативам, например, для такого `variant`.
```c++
struct foo {
    foo(foo const&);
    int a;
    double b;
}
using type = std::variant<int, char, double, foo>;
void copy (type& a, type const& b) {
    a = b;
}
```

Аналогично с деструктором и т.д.

Какие гарантии исключений у операций с `variant`? Это зависит от того, как реализовать его.

### Реализация variant

Можно предположить что-то такое (на самом деле сделано не так):

```c++
template <typename A, typename B>
struct variant {
    variant& operator=(variant const& other) {
        destroy_current();
        construct_new(other); // какие гарантии, если исключение?
    }
    std::aligned_storage_t<std::max(sizeof(A), sizeof(B)),
    						std::max(alignof(A), alignof(B))> storage;
};
```

При дизайне `variant` возникает вопрос, стоит ли разрешать делать его таким, что он не содержит ни одного из значений.

Если такого значения нет, то не понятно, что должен делать дефолтный конструктор. Помимо этого, "пустое состояние" даёт возможность сделать weak-гарантии у оператора присваивания (так как есть какое-то состояние, в которое переходит `variant`, если старый объект разрушили, а новый создать не получилось). Но пустое состояние иметь не очень хорошо - изначально мы делали `variant`, когда боролись с неинициализированной переменной. Здесь можно провести аналогию между пустым состоянием `variant`'a и нулевым указателем - если функция принимает указатель, не понятно, правда ли, что он всегда ненулевой. Очень часто люди считают, что указатель должен быть ненулевым (например, `printf`). - аналогично с `variant`.

Для функций, где `variant` мог бы стать пустым при исключении, можно просто сделать базовые гарантии.

Можно ли как-нибудь реализовать `variant` так, чтобы у него не было пустого значения, но  гарантии оператора присваивания были хотя бы *weak* (либо *strong*)?

Один из подходов (в Boost делали так): хранить два стораджа (*double buffering*). Минус такого решения - занимает в 2 раза больше места, зато можно сделать *strong* гарантии.

Ещё одна возможная реализация -  с динамической аллокацией:

```c++
template <typename A, typename B>
struct variant {
	variant& operator=(variant&& other) {
        void* p = copy_current_to_dynamic();
        destruct_current();
        try {
            construct_new(std::move(other));
        } catch (...) {
            current = p;
            throw;
        }
        
        void* move_current_to_dynamic() {
            switch (index) {
                case 0: {
                        A* p = new A(std::move(current.a_static));
                        current.a_static.~A();
                        return p;
                    }
                case 1: {
                        B* p = new B(std::move(current.b_static));
                        current.b_static.~B();
                        return p;
                    }
            }
        }
        delete p;
    }
    size_t index;
    union {
        A a_static;
        B b_static;
        A* a_dynamic;
        B* b_dynamic;
    }
};
```

Минус такого подхода в том, что возникает слишком много случаев при операциях обращения.

В`Boost.Variant1` использовали double buffering, в `Boost.Variant2` использовали подход как в примере выше.

В `std::variant` сделали пустое значение, но спрятанное в интерфейсе. Одним из ключевых предложений для `std::variant`было сделать его таким, что это невалидное состоятоние у него появляется [крайне редко](http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2015/p0088r0.pdf), а обращение к нему в таком состоянии - UB. Часть комитета была против, поэтому был принят компромиссный вариант с пустым `variant` и бросанием исключения при попытке извлечь из него значение.

В итоге у `std::variant` есть метод `valueless_by_exception()`. В `get` и `get_if` это не замечается, в `visit` бросается исключение, дефолтный конструктор `variant` не создаёт объект пустым, а использует первую альтернативу. Основная идея в том, что если выбрасывается исключение, то ожидается, что variant в таком состоянии живёт до обработки исключения, где его нужно привести в валидное состояние.

На эту тему есть интересный пост ["The Variant Saga: A happy ending?"](https://isocpp.org/blog/2015/11/the-variant-saga-a-happy-ending) от автора proposal по variant в стандартную библиотеку.

Иногда может захотеться иметь явное пустое состояние (например, если у всех типов нет дефолтных конструкторов). Для этого есть helper-класс `std::monostate`.

## tuple, pair

Частный случай `tuple` - `std::pair`. По сути, это просто структура из двух мемберов - `fist` и `second`. Например, пару возвращает `insert` у мапы, кроме того, парами являются и `value_type` у мапы (из ключа и значение).

```c++
int main() {
    std::map<std::string, int> m;
    auto p = m.insert({"abc", 42}); // std::pair<iterator, bool>
    p.first;
    p.second;
    
    std::pair<std::stirng, int> x("abc", 42);
}
```

По сути, `tuple` - структура, у полей которой нет имён, можно сказать, что это обощение пары на `n` элементов.

Пример, когда он может быть полезен:

```c++
void print(std::string const& str) {
	std::cout << str;
}

int main() {
    print("hello, world");
	auto f = std::bind(print, std::string("hello, world")); // фиксирует аргумент у функции
    f();
}
```

`bind` можно реализовать следующим образом::

```c++
template <typename F, typename Arg>
struct bound {
    bound(F&& f, Arg&& arg)
        : f(std::forward<F>(f), std::forward<Arg>(arg)) {}
    
    auto operator()() const {
        return f(arg);
    }
  prviate:
    F f;
    Arg arg;
};

template <typename F, typename Arg>
auto bind(F&& f, Arg&& arg) {
    return bound<std::decay_t<F>, std::decay_t<Arg>>
        (std::forward<F>(f), std::forward<Arg(arg));
}

template <typename F, typename Arg>
bound<F, Arg> bind(F&& f, Arg&& arg) {
    return bound<F, Arg>(std::forward<F>(f), std::forward<Arg>(arg));
}
```

Чтобы обобщить это на несколько аргументов, можно хранить в `bound` `tuple` из аргументов и использовать функцию `std::apply(f, args)` - она раскрывает `tuple` в аргументы и вызывает функцию `f`.

Обычно `tuple` реализован через наследование, рекурсивно:

```c++
struct tuple : V0, tuple<Vs...>
{}
```

## string_view

### Мотивирующий пример

Пример реализации хэш-функции [FNV](https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function):

```c++
uint32_t const offset_basis = 0x811c9dc5u;
uint32_t const prime = 0x01000193u;

uint32_t fnv1a(std::string const& str) {
    uint32_t result = offset_basis;
    for (char c : str) {
        result ^= static_cast<uint8_t>(c);
        result *= prime;
    }
    return result;
}

int main() {
    fnv1a("hello"); // конструируется string, лишняя аллокация
}
```

Такая реализация не очень подходит, если передаётся строковый литерал.

Можно было бы сделать реализацию от `char const* data` и размера, а остальные через неё - это самая общая и эффективная перегрузка. Проблема в том, что такую функцию не очень удобно вызывать, например, от литералов, так как каждый раз нужно указывать размер.

К чему это всё? Часто встречаются такие Си-стайл функции, которые принимают указатель и размер, но синтаксис не подразумевает, что указатель и размер как-то связаны. Для отражения этой идеи в стандартной библиотеке в  C++17 появился класс `std::string_view`:

```c++
struct string_view {
    // ...
    char const* data;
    size_t size;
};
```

С помощью него можно переписать функцию следующим образом:

```c++
uint32_t fnv1a(std::string_view str) {
    uint32_t result = offset_basis;
    for (size_t i = 0; i != str.size(); ++i) {
        result ^= static_cast<uint8_t>(str[i]);
        result *= prime;
    }
    return result;
}
int main() {
    fnv1a("hello");
    std::string s("hello");
    fnv1a(s);
}
```

Поскольку `string_view` не владеет данными, а просто ссылается на них, то для него действуют те же ограничения, что и для указателей: пока он ссылается на какие-то данные, они должны существовать.

Ещё один пример применения`string_view`  - "сослаться" на подстроку.

### Касты

Интересно, что то, как приводится `std::string` и `std::string_view` отличается от приведения к `char const*`:

- `char const*` в `std::string` - implicit
- `std::string` в `char const* `- `.c_str()`

- `std::string_view` в `std::string` - explicit
- `std::string` в `std::string_view` - implicit

Кажется, что и `char const*`, и `std::string_view` не владеют данными, а просто ссылаются на них, но почему-то в приведении ведут себя по-разному. С практической точки зрения понятно, почему конверсия в `std::string_view` implicit - так можно передавать строки в функции, которые принимают `string_view`.

### user-defined literals

В C++11 появился механизм, который позволяет писать user-defined literals для пользовательских классов. Этот механизм применяется в стандартной библиотеке для суффиксов строковых литералов:

```c++
void print(std::string_view str) {
    std::cout << str;
}

int main() {
    using namespace std::literals;
    std::bind(print, "hello"s); // s - std::string
    print("abc"sv); // sv - string_view
}
```

Реализовано это как `operator""sv` с разными перегрузками:

```c++
string_view operator""sv(const char* str, size_t len).
```

Суффиксы, которые не начинаются с подчеркивания, зарезервированы для стандартной библиотеке. Поэтому, если использовать без подчеркивания, то будет ворнинг, потому что в каком-то из компиляторов суффикс может быть уже занят расширением стандартной библиотеки.