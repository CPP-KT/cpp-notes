# `optional`, `variant`, `tuple`, `string_view`.

- [Запись лекции №1](https://www.youtube.com/watch?v=bJl0xlPdPj0)
- [Запись лекции №2](https://www.youtube.com/watch?v=NAA0z66IEvE)
- [Запись лекции №3](https://www.youtube.com/watch?v=hrUtXP1sZXk)
- [Запись лекции №4](https://www.youtube.com/watch?v=Dp2AIvae27M)

## `optional`.

### Мотивация.

Пусть у нас есть какой-то класс, который позволяет отложить какое-то вычисление. Понятно, что его просто реализовать так:

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

Проблема такого кода — две переменных, связь которых не очень очевидна, если они будут в составе какого-нибудь большого класса. Если это не очевидно для компилятора, то будет плохо оптимизациям. И третье: в такой реализации нужно, чтобы значение было DefaultConstructible, хотя нам это совершенно ни к чему.

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

### Базовые операции `std::optional`.

```c++
template <typename T>
struct optional {
    optional() : is_initialized(false) {}
    optional(T value) : is_initialized(true) {
        new (&storage) T(std::move(value));
    }
    ~optional() {
        if (is_initialized) {
            reinterpret_cast<T&>(storage).~T();
        }
    }
private:
    bool is_initialized;
    std::aligned_storage_t<sizeof(T), alignof(T)> storage;
};
```

В стандартной библиотеке у `optional` также есть конструктор и метод `emplace`, создающие объект уже внутри `optional` (полезно, если объект дорого копировать и перемещать).

```c++
template <class... Args>
constexpr explicit optional(std::in_place_t, Args&&... args);
// std::optional<std::string> opt(std::in_place, 3, 'A'); constructs std::string(3, 'A')
```

У него есть дополнительный аргумент `std::in_place_t`, который нужен, чтобы различать, передают аргументы для конструктора объекта `T` или просто для `optional`.

Разыменование пустого `optional` это UB, но есть метод `value`, который бросает исключение.

У `std::optional` вообще есть куча полезного (`operator->`, например), но это вы всё можете сами прочитать на [cppreference](https://en.cppreference.com/w/cpp/utility/optional), а мы обсудим не столь очевидные вещи.

### Детали работы. `noexcept`.

Посмотрим на наивную реализацию `optional`'а, а точнее на конструктор и оператор перемещения. Очень частно они не могут кинуть исключение, и это важно, потому что для `nothrow_move_constructible`-типов можно применить некоторые оптимизации (например, small-object optimization в `std::function`). И нам хочется, чтобы `optional<T>` обладал свойством `std::nothrow_move_constructible` всегда, когда может. А может он, как несложно заметить, тогда, когда таким свойством обладает тип `T`.

Вторая функция `noexcept` — документирующая, когда нам хочется полагаться на это корректности программы ради. А ещё давайте вспомним zero-cost исключения. На самом деле даже если исключений нет, то их возможность стоит нескольких процентов скорости (почему — вопрос; возможно, нужно меньше переупрядочивать код, возможно, это артефакты, но тем не менее эффект наблюдается) и довольно много стоит по размеру
файла. А `noexcept` позволяет избавляться и от этой проблемы.

Ну, хорошо. А как пометить функцию как `noexcept` лишь иногда? Для этого есть такой синтаксис: `noexcept(condition)` — `noexcept` тогда и только тогда, когда выполнено условие. А ещё, кстати, можно проверить, является ли какое-то выражение `noexcept`: `noexcept(expression)`, поэтому если вы хотите сделать условный `noexcept`, но у вас нет трейта под какую-то операцию, напишите `noexcept(noexcept(expression))`, и будет вам счастье:

```c++
optional(optional&& other) noexcept(std::is_nothrow_move_constructible_v<T>)
    : is_initialized(other.is_initialized) {
    if (is_initialized)
        new (&storage) T(*other);
}
optional& operator=(optional&& other)
noexcept(std::is_nothrow_move_constructible_v<T>
&& std::is_nothrow_move_assigneble_v<T>) {
    if (is_initialized) {
        if (other.is_initialized)
            **this = std::move(*other);
        else {
            reinterpret_cast<T&>(storage).~T();
            is_initialized = false;
        }
    } else
        if (other.is_initialized) {
            new (&storage) T(std::move(*other));
            is_initialized = true;
        }
}
```

#### Интересный факт про `noexcept`.
Ещё одна операция, которую очень полезно делать `noexcept` — подсчёт хэша. Причина проста: когда у нас происходит перехэширование, нам надо посчитать много хэш-кодов, и если вы при этом можете исключение бросить, перехэширование не работает, поэтому рядом с каждым элементом начинают хранить хэш-код.

### Тривиальные операции.

Рассмотрим два класса:

```c++
struct foo {
    int a, b;
};
struct bar {
    int a, b;
    ~bar() {}
};
```

В чём разница? В том, что на `foo` можно не вызывать деструктор при уничтожении, а на `bar` — надо. С точки зрения компилятора эти два типа отличаются тем, что `foo` не имеет никакого деструктора, а `bar` имеет деструктор, и это обычная функция (но так уж сложилась, что она ничего не делает).\
Говорят, что класс обладает тривиальным деструктором, если
- Деструктор не написан (т.е. сгенерирован автоматически) или явно прописан как `default`.
- Деструктор не виртуальный.
- Деструкторы всех баз тривиальны.
- Деструкторы всех нестатических полей тривиальны.

Аналогично определяется тривиальность обоих копирований, обоих перемещений и создания по умолчанию.

Когда тривиальность нам важна? Ну, во-первых, это необходимо для некоторых классов (например, в `std::atomic` вы можете запихать любой созданный вами тип, если он тривиально копируется). Во-вторых, тривиальное копирование — это когда копирование равносильно `memcpy`, а значит при реаллокации вектора можно просто этот `memcpy` и сделать, а не в цикле что-то вызывать, что ускоряет программу.\
И на что тривиальность влияет — так это на ABI. Тривиально-разрушаемый тип можно в регистрах вернуть, а нетривиально-разрушаемый придётся передавать параметром в функцию и конструировать на памяти. В этом и кроется причина того, что `~bar() {}` не является тривиальным деструктором — это другой ABI.  На тему ABI можно ещё посмотреть презентацию [«There are no zero-cost abstractions»](https://www.youtube.com/watch?v=rHIkrotSwcc) и увидеть, что у нас даже `unique_ptr` из-за нетривиального разрушения не может быть возвращён из функции через регистры как указатель.

#### Реализация `optional`'а.

Итак, что нам хочется? Нам хочется сделать так, чтобы когда `T` тривиально разрушается, то `optional<T>` — тоже тривиально разрушается. Как это сделать? `enable_if`? Ну, для деструктора это не сработает совсем, а если сделать шаблонные конструктор копирования, то это будет уже не конструктор копирования, и компилятор сгенерирует свои.\
Можно взять и сделать специализацию `optinal`'а, но у нас 6 операций, которые могут быть тривиальными, и у 5 из них хочется сохранить свойства. Поэтому нам придётся написать 32 варианта `optinal`'а, что совершенно огромное дублирование кода.

А правильное решение выглядит так: можно создать несколько шаблонных баз и просто отнаследовать от одной из них в зависимости от тривиальности копирований/разрушения/перемещений... Вот пример для деструктора:

```c++
template <typename T>
struct optional_storage {
    bool is_initialized;
    std::aligned_storage_t<sizeof(T), alignof(T)> storage;
};

template <typename T, bool TriviallyDestructible>
struct optional_base : optional_storage<T> {
    ~optional_base() {
        if (this->is_initialized) {
            reinterpret_cast<T&>(this->storage).~T();
        }
    }
};

template <typename T>
struct optional_base<T, true> : optional_storage<T> {
    ~optional_base() = default,
};

template <typename T>
struct optional : optional_base<T, std::is_trivially_destructible<T>> {  
    // ...
};
```

### SFINAE-friendly.

Ну, хорошо, с нашим `optional<T>`'ом уже можно жить. Но у него всё ещё есть недостаток. Что будет, если `T` не копируется в принципе? Ну, при попытке скопировать `optional` мы схватим ошибку компиляции его копирующего конструктора. Выглядит неплохо, да вот только если мы попытаемся откуда-то извне узнать, копируется ли `optional`, при помощи `std::is_copy_constructible_v`, то нам скажут, что да (ну а что, конструктор есть же).

Так вот если снаружи можно проверить, всё ли будет хорошо при вызове функции с заданным параметром (в нашем случае при вызове метода с заданным параметром шаблона), то такая функция называется **SFINAE-friendly**.

Как можно было бы реализовать это для `optional`'а? Да тривиально, у нас есть два варианта базы, отвечающей за копирование, давайте будет три.

### Conditionally-explicit конструктор.

Теперь наш `optional` уже почти хороший, но у `optional<T>` есть конструктор от `optional<U> const&`. Причём хочется, чтобы он мог быть явным или неявным в зависимости от того, конвертируется ли `U` в `T` явно или нет.

Это пишется тривиально в C++20 (там у `explicit` тоже можно логическое выражение написать), но существенно труднее в более ранних версиях. Вот пример для C++20:

```c++
template <typename U, std::enable_if_t<std::is_constructible_v<T, const U&>, bool> = true>
explicit(!std::is_convertible_v<const U&, T>)
optional(optional<U> const& other) {
    if (other)
        emplace(*other);
}
```

~~И после этого наш `optional` уже норм.~~ Оп, обманул, нам ещё `constexpr`'ы нужны, чтобы реализовать его до конца. О них [позже](./26_constexpr.md).

## `variant`.

Помните [мотивацию `optional`'а](#мотивация)? Там был класс `deferred_value`, который хранил либо значение, либо ничего. Но разве тот класс, что мы там сделали, был удобен? Да чёрта с два, мы обычно функцию в конструктор передавать хотим. То есть нам надо, чтобы мы хранили не `T` либо ничего, а `T` либо `std::function<T ()>`.

Такое можно было бы сделать с помощью `union` и пометки о том, какая альтернатива сейчас хранится. Для этого в стандартной библиотеке уже есть класс `std::variant`. 

```c++
template <class compute_func_t, class T>
struct deferred_value {
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

### Вариации `variant`'а.

Есть ровно один адекватный вариант написать `optional`. Например, в `boost`'е он был до включения в стандарт и не отличался ничем. А вот с `variant`'ом это не так! Вон, в boost'е, например, есть `variant` и `variant2`, которые концептуально оба `variant`, но работают по-разному.

Например, когда мы присваиваем в `variant` тот тип, что там уже есть, мы должны разрушить тип и пересоздать или использовать `operator=`? В `optinal`'е первое, а в `variant`'е были ожесточённые споры на эту тему. В той форме, что он в стандарте — он использует присваивание.

#### Заруба 1.

Второй вопрос: вот мы присваиваем в `variant` не то, что там есть. Если мы разрушим то, что там было, и создадим новое, это не exception-safe. Что можно с этим сделать?

1. Добавить в `variant` некорректное состояние (тогда гарантия исключений будет слабая, но лучше, чем ничего). Это довольно неплохо, но людей очень смущает некорректное состояние. Это как `null` в Java. С ним можно жить, но хотелось бы в типах информацию кодировать, а не в контракте писать, что `variant` должен быть не пуст. Ещё базовая гарантия исключений — не очень круто, в следующих вариантах будет лучше.
2. Если тот тип, что мы присваиваем, не бросает при перемещении, то можно это абьюзить, но если нет, то непонятно, как жить. Так что можно **потребовать** noexcept-move, но это явно не хорошо.\
Можно доопределить, что тот, кто бросил — сам виноват, и это UB либо `std::terminate`, но оба варианта плохи: требовать `std::noexcept_move_constructible` — совсем плохо (дебажные коллекции, например, выделяют память под контрольный блок при любом конструкторе), а `terminate` или UB не стоит делать там, где мы потенциально можем проверить, что происходит.
3. Стратегия из `boost::variant2`. Пусть у нас есть `variant<A, B>`. Давайте введём не некорректное состояние, а добавим возможность хранить не только `A` и `B`, но и `A*` и `B*`. И тогда мы перемещаем `A` в новый указатель, попытаемся присвоить `B`, если у нас не, получится, вернёмся в состояние `A`, но на самом деле это будет `A*`. Эта стратегия называется **«heap backup»**.\
Из плохого тут разве что потенциально ненужная аллокация (исключения должны быть редкими), происходящая всегда.
4. **«Double buffering»**. Стратегия из `boost::variant1`. То же самое, что и раньше, но копию мы делаем не на куче, а в поля кладём точно такой же `storage`, и копируем в него. Тут понятно, чего плохо — вдвое больше памяти используем. Если такой `variant` один, то можно пережить, но если их много, то не надо, пожалуйста.

Реализация упрощённого `variant`'а с использованием heap backup:
```c++
template <typename A, typename B>
struct either {
	either& operator=(either&& other) {
        void* p = move_current_to_dynamic();
        destruct_current();
        try {
            construct_new(std::move(other));
        } catch (...) {
            current = p;
            throw;
        }
        delete p;
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
    size_t index;
    union {
        A a_static;
        B b_static;
        A* a_dynamic;
        B* b_dynamic;
    }
};
```


И вот по этому поводу и происходили зарубы, что же из этого выбрать. Конкретно в `std::variant` вделано некорректное состояние. Но там его ещё чуть допилили. Некорректное состояние можно сделать по-разному: можно сказать, что некорректное состояние — это полноценное состояние, а можно сказать, что оно [очень редко](http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2015/p0088r0.pdf) происходит и из него работает только ограниченный набор методов. И в стандартной библиотеке пошли вторым путём. Более того, его ещё сильнее спрятали: в конструкторе по умолчанию у нас создаётся первая альтернатива (вместо того, чтобы создавать его в некорректном состоянии). Вообще по этой теме можно посмотреть [видос с CppNow](https://www.youtube.com/watch?v=JUxhwf7gYLg) или почитать [пост "The Variant Saga: A happy ending?"](https://isocpp.org/blog/2015/11/the-variant-saga-a-happy-ending) от автора proposal по `variant`'у в стандартную библиотеку.

А если вам явно нужно пустое состояние (честное и хорошее), то вам в руки дали `std::monostate` — пустую структурку.

#### Заруба 2.

А как определить сравнение? Можно сравнить сначала по номеру альтернативы, а потом по значению, но тут возникают такие странности:

```c++
variant<int, long> a = 10;
variant<int, long> b = 5L;
assert(a < b);
```

Тогда можно попытаться определить `<` для каждой пары типов, что у нас есть, но это квадратичное количество кода. И как бы ладно с `<`. А вот что с `==`?

```c++
variant<int, long> a = 10;
variant<int, long> b = 10L;
assert(a != b);
```

И тут вопрос возникает ещё интереснее, можно ли сделать `variant<int, int>`?

В STL разрешён `variant<int, int>`, а `<` и `==` сравнивают сначала по номеру альтернативы, потом по значению. Некорректное состояние считается раньше всех. Оно, кстати, называется
`valueless_by_exception`.

### Паттерн визитёров.

Когда-то давно мы [обсуждали](./07_inheritance.md#наследование-против-unionа), что `union` (а точнее, `variant`) можно применять для тех же целей, что виртуальные функции — делать что-то для каждой альтернативы. Но как это сделать для `variant`'а, не кучкой `if`'ов же?

Нет, не кучкой `if`'ов. Чтобы избежать такого, используется паттерн **visitor**. 

```c++
struct visitor {
    void operator()(A const&) const { /* ... */ };
    void operator()(B const&) const { /* ... */ };
    void operator()(C const&) const { /* ... */ };
};

int main() {
    std::variant<A, B, C> v;
    std::visit(visitor(), v);
}
```

Это не очень удобно, так как приходится создавать новый класс. Можно ли сделать это с помощью лямбд? К сожалению, у них нет перегрузок, но это можно реализовать отдельно:

#### Паттерн перегрузок.

```c++
template <typename A, typename B> // A, B — любые функциональные объекты
struct overloaded : A, B {
    using A::operator();
    using B::operator();
}
```

Это называют **overload pattern**, который в общем случае выглядит как-то так:

```c++
template <class... Fs>
struct overload;

template <class F0>
struct overload<F0> : std::remove_reference_t<F0> {
    overload(F0&& f0)
        : F0(std::forward<F0>(f0)) {}
    using std::remove_reference_t<F0>::operator();
};

template <class F0, class... Frest>
struct overload<F0, Frest...> : std::remove_reference_t<F0>, overload<Frest...> {
    overload(F0&& f0, Frest&&... frest)
        : F0(std::forward<F0>(f0)),
    	  overload<Frest...>(std::forward<Frest>(frest)...) {}
    using std::remove_reference_t<F0>::operator();
    using overload<Frest...>::operator();
}

template <typename... Funcs>
overload<Funcs...> make_overload(Funcs&&... funcs) {
    return overload<Funcs...>(std::forward<Funcs>(funcs)...);
}
```

У этой штуки есть проблема в том, что она не работает для указателей на функции, но, я верю, что вы сами справитесь это поправить.

Про `std::visit` и *overload pattern* есть интересная статья ["std::visit is everything wrong with modern C++"](https://bitbashing.io/std-visit.html).

На [cppreference](https://en.cppreference.com/w/cpp/language/using_declaration) приведён пример такого `overload`:

```c++
template <typename... Ts>
struct Overloader : Ts... {
    using Ts::operator()...; // exposes operator() from every base
};
 
template <typename... T>
Overloader(T...) -> Overloader<T...>; // C++17 deduction guide, not needed in C++20
// нужно, чтобы выводились шаблонные параметры класса

int main() {
    auto o = Overloader{ [] (auto const& a) {std::cout << a;},
                         [] (float f) {std::cout << std::setprecision(3) << f;} };
}
```

*Note*: такой `Overloader` является [aggregate](https://en.cppreference.com/w/cpp/language/aggregate_initialization), поэтому ему можно не писать конструктор и инициализировать базовые классы через `{}`.

## `tuple`, `pair`.

`std::pair` — это понятно, кто: просто структурка из двух полей — `first` и `second`. Используется, например, как возвращаемое значение `std::map<K, V>::insert`. Или, ещё пример, `std::map<K, V>::value_type` также являются парами (из ключа и значения).

```c++
int main() {
    std::map<std::string, int> m;
    auto p = m.insert({"abc", 42}); // std::pair<iterator, bool>
    p.first;
    p.second;
    
    std::pair<std::string, int> x("abc", 42);
}
```

Больше про `std::pair` сказать так-то и нечего, это не очень интересная структура.\
То ли дело `std::tuple`. Это тоже структура, но у её полей нет имён. Можно считать, что это обобщение пары на произвольное количество элементов.

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
private:
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

Чтобы обобщить это на несколько аргументов, можно хранить в `bound` `tuple` из аргументов и использовать функцию `std::apply(f, args)` — она раскрывает `tuple` в аргументы и вызывает функцию `f`.

Обычно `tuple` реализован через наследование, рекурсивно:

```c++
template <class V0, class... Vs>
struct tuple<V0, Vs...> : V0, tuple<Vs...>
{}

template <>
struct tuple<> {}
```

## `string_view`.

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

Можно было бы сделать реализацию от `char const* data` и размера, а остальные через неё, т.к. это самая общая и эффективная перегрузка. Проблема в том, что такую функцию не очень удобно вызывать, например, от литералов, так как каждый раз нужно указывать размер.

К чему это всё? Часто встречаются такие Си-стайл функции, которые принимают указатель и размер, но синтаксис не подразумевает, что указатель и размер как-то связаны. Для отражения этой идеи в стандартной библиотеке в C++17 появился класс `std::string_view`:

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

Ещё один пример применения`string_view` — "сослаться" на подстроку.

### Приведения.

Интересно, что то, как приводится `std::string` и `std::string_view` отличается от приведения к `char const*`:

- `char const*` в `std::string` - implicit
- `std::string` в `char const* `- `.c_str()`

- `std::string_view` в `std::string` - explicit
- `std::string` в `std::string_view` - implicit

Кажется, что и `char const*`, и `std::string_view` не владеют данными, а просто ссылаются на них, но почему-то в приведении ведут себя по-разному. С практической точки зрения понятно, почему конверсия в `std::string_view` implicit - так можно передавать строки в функции, которые принимают `string_view`.

### User-defined literals.

В C++11 появился механизм, который позволяет писать литералы для пользовательских классов. Этот механизм применяется в стандартной библиотеке для суффиксов строковых литералов:

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

Суффиксы, которые не начинаются с подчеркивания, зарезервированы для стандартной библиотеке. Поэтому, если использовать без подчеркивания, то будет предупреждения, потому что в каком-то из компиляторов суффикс может быть уже занят расширением стандартной библиотеки.
