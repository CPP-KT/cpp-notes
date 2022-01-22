# Концепты

- [Запись лекции №1](https://youtu.be/KNF4j-lz_Do)
- [Запись лекции №2](https://youtu.be/i6rR_kEBQGc)

## Проблемы обычных шаблонов
Иногда нам хочется чтобы шаблон инстанцировался только от определённых типов
(например `vector<int&>` не имеет смысла).

## Почему концепты могут быть полезны
Во-первых, упрощаются сообщения об ошибках при неправильном инстанцировании
(пример - `std::vector<int&>`).
Во-вторых, концепты компилируются обычного SFINAE.
Ещё есть не SFINAE-friendly типы, которые могут удовлетворить какому-нибудь
`std::is_nothrow_copyable_v` но по факту бросать исключение. Ещё бывает, что
типы параметры типов как-то связаны между собой но эта связь не выразима
трейтами (`std::sort(begin, end)` ничего не скажет, если мы дадим итераторы двух
разных типов).

## Explicit vs implicit концепты
Достаточно ли написать деструктор, чтобы тип считался destructible? И не всегда
можно по итератору определить, какого он вида. Тут не обойтись без explicit
концептов.
В Concept GCC пытались делать definition-checking, т.е. проверяли, какими
свойствами должен обладать шаблонный тип (наличие оператора `>` и т.п.). И это
работало очень медленно.

## `concept_map`
Например, `vector` может реализовывать концепт `stack` и в соответствие
операциям `push` и `pop` мы могли бы поставить `push_back` и `pop-back`. Или мы
могли бы сделать `T*` итератором, объявив для него `value_type` равным `T` и
т.п. Вот это и называется `concept_map`.

## Проблемы ранних концептов
Изначально хотели сделать систему концептов с наследованием:
```c++
concept C1 : C2 {
    ...
};
```
Но вскоре поняли, что какой-то безобидный концепт мог потащить за собой кучу
других и нам пришлось бы реализовывать всю ненужную функционалност.
Ещё одна проблема - концептуализация стандартной библиотеки. Например,
`std::sort` использует оператор `<` и через него выражает все остальные пять.
Это сделано для того, чтобы пользователь мог реализовать только необходимый
минимум. В случае же какого-нибудь `comparable` концепта, пришлось бы писать все
шесть операторов сравнения. Поэтому концепты стали дробить и их стало слишком
много. В итоге концепты перестали дробить.

## Concepts Lite
- [Proposal](http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3701.pdf)
Концепты вошли в язык из пропозала выше, `concept_map` решили убрать.

Синтаксис:
```c++
template <typename T>
concept destructible = std::is_nothrow_destructible_v<T>;
```

Полная форма:
```c++
template <typename T>
requires destructible<T>
void f(T&);
```

Короткая форма:
```c++
template <destructible T>
void f(T&);
```

Можно даже ещё короче:
```c++
void f(destructible auto&);
```

В общем случае объявление выглядит так:
```c++
// Запись:
template<C X>
// Эквивалентна
template<typename X>
requires C<X>

// А запись
template<C auto X>
// Эквивалентна
template<auto X>
requires C<X>
```
Выражение вида `requires expr` называется requieres clause.

Как проверить, что тип поддерживает какую-то операцию? Для этого существует
requieres expression:
```c++
template <typename T>
concept comparable = requires(T a)
// compound requirement
{
 {a < a} -> std::convertible_to<bool>;
};
```
Внутри requires expression можно проверить валидность и свойства какого-то
выражения (как в примере выше - compound requirement), наличие функции
(`begin(a)` - simple requirement) либо наличие типа (`typename T::value_type` -
т.н. type requirement).

## Специализации (или как это здесь называется)
Рассмотрим варианты функции `advance`:
```c++
void advance(input_iterator auto&, ptrdiff_t);
void advance(random_access_iterator auto&, ptrdiff_t);
```
Как компилятор понимает, какая специализация "уже"? Для этого в стандарте
определяется специальный
[алгоритм](https://en.cppreference.com/w/cpp/language/constraints) (см. partial
ordering of constraints).

## Применение
С 34 минуты второй лекции начинается godbolt (ничего не видно, но можно
послушать): примеры с `comparable`, свой `same_as`.
Потом обсуждается [презентация](https://youtu.be/vYzjV0xSqJE) Андрея Давыдова по
концептам (пример с дефолтным конструктором pair).
Проблема `enable_if` в конструкторах - выключать их не просто. Например, мы
решали эту проблему в `optional` наследованием + `conditional` и т.д. Зато с
помощью концептов эта проблема решается тривиально:
```c++
template<typename T> class optional {
    ...
    optional(optional const&) requires(!CopyConstructible<T>) = delete;
    optional(optional const&) requires(TriviallyCopyConstructible<T>) = default;
    optional(optional const&) noexcept(NothrowCopyConstructible<T>) { ... }
    ...
}
```

## Поддержка у компиляторов
gcc-10, clang-10, msvc (2019.09-2021.03)
