# Шаблоны.
- [Запись лекции №1](https://www.youtube.com/watch?v=AXl4_eZ1eis)
- [Запись лекции №2](https://www.youtube.com/watch?v=DwDbH7pxzRA)
- [Практика](https://www.youtube.com/watch?v=CY7vxMSBork)
- [Запись ещё одной лекции](https://www.youtube.com/watch?v=HQdf43h3B2o)
---

## Мотивация.
Часто очень хочется делать типизированный класс - например, какую-то структуру данных для разных типов. Здесь и применяются шаблоны.

## Способы жить без шаблонов.
В C шаблонов не было и было два способа жить без них

### `void*`.
В C есть `void*` — тип указателя, который (в C, не C++) неявно преобразуется куда угодно и откуда угодно. И тогда всё выглядело бы так:
```c++
struct vector {
	void push_back(void*);
	void*& operator[](size_t index);
	const void*& operator[](size_t index) const;
};

int main() {
	point* p;
	vector v;
	v.push_back(p);
	static_cast<point*>(v[0]);
}
```
У этого есть следующие проблемы:
- Это не типобезопасно. Мы можем достать из вектора не то, что туда положили. И компилятор ничего не скажет. А если мы можем выявить ошибку на этапе компиляции, сто́ит это делать.
- Количество аллокаций. Если мы хотим хранить целые числа, а не указатели, в `std::vector<int>` мы тупо выделяем большой блок памяти, а в нашем `vector`'е мы сначала выделяем большой блок под указатели, а потом выделяем память под каждый. К тому же подобную штуку не получится prefetch'ить, потому что память под каждый объект выделена в разных местах, а значит лишний indirection.
- Следующий код не exception-safe.
```c++
	vector u;
	u.push_back(new point());
```

### Макросы.
```c++
#define DEFINE_VECTOR(vector_name, type)                       \          
struct vector_name {                                              \
	void push_back(type) { /*...*/ }                          \
	type operator[](size_t index) const{ /*...*/ }            \
};
```

Тут уже явно лучше, можно написать это типобезопасно, без проблем с памятью, но тоже имеются проблемы. Например, вот:
```c++

DEFINE_VECTOR(vector_int, int);
DEFINE_VECTOR(vector_int32_t, int32_t);
int main() {
	vector_int v;
	vector_int32_t u;
}
```
И теперь мы имеем две одинаковые структуры, а хотелось бы иметь одну там, где `int` 32-битный.

Второе — когда мы имеем `DEFINE_VECTOR(int)` в двух разных местах. Потому что вам и какому-то человеку из Австралии понадобилось одно и то же. А потом кто-то подключает и то, и другое, и он проиграл.

## Базовый синтаксис.
```c++
template <typename T>
// template <class T> это то же самое
struct vector {
	void push_back(T const &) { /*...*/ }
	T const& operator[](size_t index) const { /*...*/ }
};
```
После этого пишем `vector<int>`, и не получаем ни одну из проблем двух способов выше. Шаблоны можно навесить не только на класс, но и [на переменную](https://en.cppreference.com/w/cpp/language/variable_template) (since C++14) или функцию:
```c++
template <typename T>
void swap(T& a, T& b) {
	T tmp = a;
	a = b;
	b = tmp;
}
```
При этом для функций вы не обязаны писать `swap<int>(a, b)`, а можете написать просто `swap(a, b)`, если переменные `a` и `b` уже имеют тип `int`. При этом если вы подставите в эту функцию `long long` и `int`, вам явно напишут, что нельзя так. Более того:
```c++
template <typename Dst, typename Src>
Dst my_cast(Src s) {
	return static_cast<Dst>(s);
}
int main() {
	int x = 42;
	my_cast(x);        // Непонятно, чему равно `Dst`, ошибка.
	my_cast<float>(x); // `Dst` указан явно, `Src` можно вывести, зная тип `x`.
}
```

## Специализации.
Иногда для каких-то типов хочется сделать отдельную реализацию. Например, `vector<bool>`. Это называется *специализацией* и делается так:
```c++
template <>
struct vector<bool> {
	// ...
};
```
И у вас для всех типов, кроме `bool` будет то, что вы написали изначально, а для `bool` — специализация. При этом **когда вы пишете специализацию, вы пишете целиком новый класс**.

`vector<T>` называется *primary template*, `vector<bool>` — *explicit (или full) specialization*. А ещё есть
*partial specialization* — специализировать не обязательно все параметры. И ещё можно особым образом специализировать. Например, мы решили, что мы можем каким-то особым образом хранить указатели:
```c++
template <typename U>
struct vector<U*> {
	// ...
};
```
(То что тут параметр называется `U`, а не тоже `T`, ничего не значит.)

То есть ***partial specialization* — это специализация, сама являющаяся шаблоном**. Теперь, когда вы напишете `vector<int*>`, вам дадут специализацию `vector<U*>`.

Примечание: **в шаблоны вы можете передавать всё что угодно** (хоть `void`, хоть `int(int, int)` (функцию, даже не указатель на неё), хоть `char[]`). **Но не любой класс обязан корректно работать с любым классом.** Так `std::vector` не компилируется, если дать ему не перемещаемый тип, и не работает вполне корректно, если дать ему, ну, например, тип, который кидает исключение в деструкторе.

Впрочем, у вас есть возможность явно указать, какие типы вы принимать не хотите. Двумя способами: [SFINAE](#sfinae) и [концепты](./28_concepts.md).

### Выбор специализации.
```c++
template <typename A, template B>
struct my_type {};         // 1
template <typename A>
struct my_type<A, int> {}; // 2
template <typename B>
struct my_type<int, B> {}; // 3

int main() {
	my_type<float, double> fd; // Выбирается 1.
	my_type<float, int>    fi; // Выбирается 2.
	my_type<int,   double> id; // Выбирается 3.
	my_type<int,   int>    ii; // Компилятор не может выбрать между 2 и 3. Не компилируется.
}
```
Хм-м-м-м, тут возникает резонный вопрос: видимо, компилятор как-то выбирает «самую хорошую» специализацию, но непонятно, как определяет, какая лучше. А давайте вот на такой пример посмотрим:
```c++
template <typename T>
struct bar {}; // Произвольный тип.

template <typename U>
struct bar<U*> {}; // Указатель на что-то.

template <typename R, typename A, typename B>
struct my_type<R (*)(A, B)> {}; // Указатель на функцию.
```
Здесь есть «указатель на что-то» и «указатель на функцию». Кажется, что второе более специализированно. Но как бы это формализовать? Да легко! Является ли произвольный указатель на функцию указателем? Да. А является ли произвольный указатель указателем на функцию? Нет. То есть **если мы всегда можем корректно подставить одну специализацию в другую, но не наоборот, то первая более специализированна**.

Вопрос: что делать, если шаблон от нескольких параметров зависит? Тут **первая специализация более специализированна, чем вторая, если хотя бы по одному параметру она строго более специализированна, а по остальным — не менее**.

### Специализация функций.
Во-первых, **у функций нет partial-специализаций**. Во-вторых, есть перегрузки, и непонятно, как они со специализациями взаимодействуют.

```c++
template <typename T>
void baz(T*) {}

#if ENABLE_TEMPLATE
template <>
void baz<int>(int*) {}
#else
void baz(int*) {}
#endif
```
Чем отличаются две последних функции? Например, на таком коде:

```c++
int main() {
	foo(nullptr);
}
```
Давайте подумаем, работает ли это, если мы включим `ENABLE_TEMPLATE`. А вот не работает, потому что непонятно, чему равно `T`. А вот с перегрузкой всё работает (выбирается перегрузка). Почему это так работает, хочется спросить?

Есть перегрузки функции. Мы их проходили, и одну видим тут: `void baz(int*)`. Так вот, **шаблон (весь целиком) считается ещё одной перегрузкой**. При этом, когда вы вызываете функцию, происходит вот что:

1. Выбирается перегрузка.
2. Если выбрана шаблонная перегрузка, выбирается специализация.

Подробнее про *Template argument deduction* на [cppreference](https://en.cppreference.com/w/cpp/language/template_argument_deduction).

Поэтому когда мы подставляем `nullptr`, то из него нельзя понять, на какой тип он указывает, поэтому *deduction* провалится, и мы получаем ошибку. Если же есть `void foo(int*)`, то выбирается он, как единственный подходящий.

Кстати, можно немного изменить работу с перегрузками. Можно вызывать функции не как `foo(...)`, а как `foo<>(...)`. В таком случае вы явно отбросите всё, что не является шаблоном, а значит выбирать будете только из специализаций.


## Non-type template parameter.
Помимо типов в параметры шаблона можно пихать чиселки. Или любой другой примитивный тип либо `enum`. Простым примером является `std::array` — обёртка над C-шным массивом, который принимает два шаблонных параметра: тип, что хранить, и количество, сколько хранить:
```c++
template <typename T, size_t N>
struct array {
private:
	T data[N];
public:
	// ...
};
```
Всё также можно писать специализации:
```c++
template <typename T>
struct array<T, 0> { /*...*/ };

array<int, 10> a;
array<int, 0> a;
```
То же самое можно написать и для функций:
```c++
template <typename T, size_t N>
size_t size(T (&arr)[N]) {
	return N;
}
```
Важный момент в non-type параметрах шаблона: **всё, что вы подставляете в шаблон, должно быть известно на этапе компиляции**. Потому что только на этапе компиляции существуют типы, в частности, шаблонные типы.

## Template template parameter.
Хочется обёртку над контейнером. Зачем-то.
```c++
template </* container */ V>
struct container_wrapper {
	V<int> container;
};

container_wrapper<vector> wrapper;
```
Это пишется вот так:
```c++
template <template <typename> class V>
struct container_wrapper {
	V<int> container;
};
```
Используется эта штука очень редко. Правила работы с ней те же самые, что и обычно.

### Параметры по умолчанию.
Шаблонные параметры могут иметь дефолтные значения, они работают как и у функций:
```c++
struct default_comparer { /*...*/ }; // Вообще он называется `std::less`.
template <typename T, typename C = default_comparer>
struct set { /*...*/ };

set<int> a; // `C` = `default_comparer`.
```

## Зависимые имена.
Начнём немного издалека: если вы видели шаблонный код, то вам может показаться, что в случайных местах по нему раскиданы слова `typename` и `template`. Например, вот в таких
примерах:
```c++
	typename std::vector<T>::iterator it;
	// Вместо std::vector<T>::iterator it;
	typename foo<T>::template bar<int> y;
	// Вместо foo<T>::bar<int> y;
```
Зачем это? А давайте рассмотрим некоторые строки в вакууме:
- `(a)-b`.
- `int b(a)`.
- `a < b && c > d`.

Что в них написано? А вот непонятно. В зависимости от того, что такое `a`, есть варианты:
- `(a)-b`.
	- Вычитание `b` из `(a)`.
	- Приведение `-b` к типу `a`.
- `int b(a)`.
	- Определение переменный `b` типа `int` с конструктором от `a`.
	- Объявление функции `b`, которая принимает тип `a` и возвращает `int`.
- `a < b && c > d`.
	- Логическое выражение `(a < b) && (c > d)`.
	- Определение переменной `d` типа `a<b && c>` (шаблон с non-type параметром типа `bool`).

Если `a` — это тип, то одно, если не тип — то другое. И обычно компилятор это знает. Проблема в том, что в шаблонах мы можем сделать что-то такое:
```c++
template <typename T>
void foo(int x) {
	(T::nested) - x;
}
```
Вы не узнаете, что такое `T::nested` до подстановки. А очень хотите это знать, чтобы отлавливать ошибки раньше, чем подстановка (например, написав `(T::nested) - y`, вы не получили бы ошибку о том, что не существует `y`, сразу). Поэтому вы должны явно указать, что происходит:
```c++
template <typename T>
void foo(int x) {
	(T::nested) - x;        // Вычитание.
	(typename T::nested)-x; // Каст.
}
```
Аналогично с двумя другими примерами:
```c++
template <typename T>
void foo(int x) {
	int b(T::nested);          // Конструктор переменной.
	int b(typename T::nested); // Объявление функции.
}
```
```c++
template <typename T>
void foo(int x) {
	T::nested < b && c > d;       // Логическое выражение.
	T::template nested<b && c> d; // Переменная шаблонного типа.
}
```
При этом **когда у вас есть что-то, что не зависит от шаблона (и имеет в себе `nested`), компилятор сам определит, тип ли это**, писать `template` и `typename` не обязательно. То что зависит от шаблона, называется *dependent*. И вот **в dependent-штуках обязательно писать `typename`'ы и `template`'ы, а independent — нет**.

MSVC, кстати, долгое время делал не так (а полностью разбирал шаблонную функцию при подстановке), за что его загнобили, и больше он так не делает, а делает как все: разбирает dependent выражения при подстановке, а independent — сразу. Это называется «[*two-phase name lookup*](http://blog.llvm.org/2009/12/dreaded-two-phase-name-lookup.html)».

### Зависимые имена в базовых классах.
```c++
struct arg1 {
    struct type {}; // Нельзя складывать.
};

template <typename T>
struct base {};

template <typename T>
struct derived : base<T> {
    void f() {
        typename T::type() + 1; // Ошибка компиляции про подстановке (dependent).
        arg1::type() + 1;       // Ошибка компиляции при разборе (independent).

        x = 5;                  // Непонятно.
    }
};
```
Почему непонятно? Потому что мы можем создать специализацию `base`, у которой будет `x`, и будет корректно. А ещё этот `x` может быть глобальной переменной. Поэтому тут происходит что-то непонятное.., хотелось бы сказать, но нет.

По стандарту **компилятор ищет имя, игнорируя базовые классы** (иначе он не мог бы откидывать любые неизвестные имена). Если хотим ссылаться на `x` из базового класса, нужно писать явно `base<T>::x` или `this->x`. Тогда он, очевидно, будет depended в обоих случаях.

**В dependant-именах компилятор откладывает разбор на момент инстанцирования, даже если раньше очевидно, что есть ошибка**:
```c++
template <typename T>
struct derived : base<T> {
	void* x;
	void f() {
		this->x = 5;
	}
};
```

## Как это устроено внутри? 
На лекции очень много [godbolt](godbolt.org), поэтому посмотрите [запись](https://youtube.com/watch?v=DwDbH7pxzRA) или сами покомпилируйте.

Начнём с шаблонных функций:

```c++
template <typename T>
void swap(T& a, T& b) {
	T tmp = a;
	a = b;
	b = tmp;
}
auto p = &swap<int>; 
auto q = &swap<char>; 
```

Для каждого типа код функции генерируется отдельно. При этом, например, чтобы сделать `sizeof(swap(a, b))`, компилятору не обязательно подставлять тело функции.

### Немного про разные единицы трансляции.

```c++
// swap.h.
template<typename T>
int swap(T& a, T& b);
```
```c++
// swap.cpp.
template <typename T>
void swap(T& a, T& b) {
	T tmp = a;
	a = b;
	b = tmp;
}
```
```c++
// main.cpp.
#include "swap.h"
int main(){
	int a, b;
	swap(a, b);
}
```

Такое не скомпилируется. Почему? Каждая единица трансляции транслируется отдельно, а потом всё линкуется.

**Инстанцирование шаблонов (подстановка) происходит до линковки**. По этой причине в `swap.cpp` мы не можем сгенерить `swap<int>`, потому что не знаем, что он будет использоваться, а в `main.cpp` не может сгенерить, потому что нет её тела.

Можно определить тело шаблонной функции прямо в `swap.h` и инклудить в разные файлы. Казалось бы, получим ошибку из-за нескольких определений, но нет. **Шаблонные функции помечаются компилятором как `inline`** и не выдаёт ошибку, считая, что они все одинаковые.

В стандарте прописано, что инстанцирование происходит только когда необходимо. При этом компилятор может делать это в конце единицы трансляции:

```c++
template <typename T>
struct foo {
	T* bar;
	void baz(){
		T qux;
	}
};
int main() {
	foo<void> a; // Так скомпилируется.
	a.baz();     // Так нет, ошибка из-за `void qux;`.
}
```
В примере выше видно, что если в коде нет вызова функции `baz`, то всё компилируется, так как она не инстанцируется.

С классами работает аналогично: **полное тело класса не подставляется, если не требуется**:
```c++
template <typename T>
struct foo {
	T bar;
};
int main() {
	foo<void>* a; // Так скомпилируется.
	a->bar;       // Так нет, опять ошибка из-за `void bar;`.
}
```

#### Incomplete type.
Помните *incomplete type*? Его упоминали в конце [раздела про forward-декларации](./05_compilation.md#forward-декларации). Так вот, почему важно понимать то, что написано выше? Ну, например, мы не можем использовать `std::unique_ptr` на incomplete типе. Точнее, можем, но получим ошибку, если в коде есть вызов деструктора или другие обращение к объекту.
```c++
// mytype.h
#include <memory>

struct object;

struct mytype {
	std::unique_ptr<object> obj;
};
```
```c++
// mytype.cpp
#include "mytype.h"

struct object {
	object(int, int, int) {};
};
mytype::mytype() : obj(new object(1, 2, 3)) {}
```
```c++
// main.cpp
#include "mytype.h"
int main(){
	mytype a;
	return 0;
}
```
Без *main.cpp* компилируется, так как у `a` не вызывался деструктор, поэтому он не инстанцировался. С *main.cpp* компилятор генерирует деструктор, который вызывает деструкторы всех членов класса, а там `unigue_ptr<object>`, у которого при компиляции будет инстанцироваться деструктор. В `unique_ptr` есть специальная проверка, что если удаляется incomplete type (а у нас `object` именно таковой), то это ошибка.\
Как решить проблему? Сделать объявление деструктора в *mytype.h*, а определить его там, где `object` — complete тип (то есть в *mytype.cpp*).

Ещё пример:
```c++
template <typename T>
struct base {
	typename T::mytype a;
};

template <typename T>
struct derived : base<derived<T>> {
	typedef T mytype;
};

derived<int> a;
```
Почему это не скомпилируется? Посмотрим на пример попроще:
```c++
template <typename T>
struct base {
	typename T::mytype a;
};
struct derived : base<derived> {
	typedef int mytype;
};
```
Тоже не скомпилируется с ошибкой про incomplete type `derived`. Почему? Ну потому что `derived` является incomplete типом, когда инстанцируется `base<derived>`.

В предыдущем примере тот же самый эффект: так как `derived` шаблонный, то он не инстанцируется сразу, но когда мы инстанцируем `derived`, то он создаётся как incomplete (complete он станет после подстановки базовых классов), происходит подстановка base и получаем ошибку.

В конексте обсуждённого выше может быть интересно прочитать про идиому [CRTP](https://en.wikipedia.org/wiki/Curiously_recurring_template_pattern).


### Явное инстанцирование шаблонов.
Есть у нас стандартный нерабочий пример:
```c++
// string.h
template <class CharT>
struct basic_string {
	// ...
	const CharT* c_str();
	// ...
};
```
```c++
// string.cpp
#include "string.h"

// ...
template <class CharT>
const CharT* basic_string<T>::c_str() { /*...*/ }
// ...
```
```c++
// main.cpp
#include "string.h"

int main() {
	basic_string<char> str("abacaba");
	const char* c_str = str.c_str();
}
```
Мы уже знаем, что этот пример не скомпилируется, и знаем, почему. Но не знаем пока, как его можно поправить. А поправить его можно так:
```c++
// string.cpp
#include "string.h"

template const char* basic_string<char>::c_str();

// ...
template <class CharT>
const CharT* basic_string<T>::c_str() { /*...*/ }
// ...
```
Это *явное инстанцирование шаблона*, и является оно командой «прямо тут мне инстанцируйте то, что я попросил».

#### Подавление инстанцирования (since C++11).
Подавление явного инстанцирования, если знаем, что функции уже где-то инстанцированы и мы не хотим лишних:
```c++
extern template void foo<int>(int); 
extern template void foo<float>(float);
```

"Выдаём тело наружу и говорим, что уже проинстанцировано, `main` не будет пытаться инстанцировать функцию, так как увидит `extern` и будет работать соответствующе."

# Type-based dispatch.
В языке существует и иногда необходимо узнавать какое-то свойство у типа. Если мы пишем обобщённое возведение в степень, нужно спрашивать, что считается единицей. Или есть мы пишем операции с числами, хочется взять максимум данного типа. Очень много из такого делает стандартная библиотека: например, есть `std::advance` — функция, которая делает итератору `+=`, даже если он так не умеет, а умеет только `++`. И тут мы либо делаем `+=`, либо `++` много раз, в зависимости от типа. Надо спросить, умеет ли итератор в `+=`.

## `<numeric_limits>`
Самые простые свойства типов — `std::numeric_limits`. Это шаблонный класс, в который вы даёте численный тип, а он содержит миллион статических полей, который для данного типа дают информацию о минимуме, максимуме или чём-то ещё.

## `<type_traits>`.
Более сложные запросы к типу можно найти в заголовочном файле `<type_traits>`, где есть бесконечное количество шаблонных констант `is_trivially_destructible_v`, `is_empty_v`, и прочих других. Какие-то из встроены в компилятор, какие-то вы можете реализовать сами (`is_signed_v`, например, можете запросто). 

Как работают штуки из `type_traits`? И почему оканчиваются на `_v`? Дело в том, что до C++14 у вас не было шаблонных переменных (а по сути `is_empty_v` — шаблонная переменная и есть). Поэтому создали шаблонный класс `is_empty` со статическим полем `value`, в котором то, что вам нужно. А когда в С++14 такое появилось, вы смогли писать `is_empty_v`, и это уже реальная `bool`'евая константа, которую можно использовать.

## Наивный способ делать type-based dispatch. `if constexpr`.
Пример использования `<type_traits>`: хотим мы вызвать деструкторы всех элементов на отрезке:
```c++
#include <type_traits>

template <class T>
void destroy(T* first, T* last) {
	if (!std::is_trivially_destructible_v<T>)
		for (T* p = first, p != last; p++)
			p->~T();
}
```
Работает! Компилятор поймёт, что `if` можно на этапе компиляции посчитать, и посчитает. Но такое, увы, работает не всегда. Напишем свой `std::advance`:
```c++
#include <type_traits>
#include <iterator_traits>

template <class It>
void advance(It& it, ptrdiff_t n) {
	using category = typename std::iterator_traits<It>::iterator_category;

	// Если итератор — RandomAccess, сделаем ему +=.
	if (std::is_base_of_v<std::random_access_iterator_tag, category>) {
		it += n;
	} else {
	// Если не RandomAccess, сделаем ++ или -- несколько раз.
		while (n > 0) {
			--n;
			++it;
		}
		while (n < 0) {
			++n;
			--it;
		}
	}
}
```
Проблема тут очевидная — компилируются всё равно обе ветки, и первая не компилируется для `std::list<T>::iterator`, потому что он не умеет в `+=`. В C++17 есть простое решение этой проблемы: **`if constexpr` — работает как `if`, но только с compile-time константами, и при этом компилируется только нужная ветка**. Но так сделать у вас есть возможность не всегда.

## Iterator dispatch.
А давайте вот как схитрим:
```c++
#include <iterator_traits>

template <class It>
void advance_impl(It& it, ptrdiff_t n, std::random_access_iterator_tag) {
	it += n;
}

template <class It>
void advance_impl(It& it, ptrdiff_t n, std::input_iterator_tag) {
	while (n > 0) {
		--n;
		++it;
	}
	while (n < 0) {
		++n;
		--it;
	}
}

template <class It>
void advance(It& it, ptrdiff_t n) {
	using category = typename std::iterator_traits<It>::iterator_category;
	advance_impl(it, n, category());
}
```
То есть мы передаём лишний параметр — одну их двух пустых структур, в зависимости от которой выбирается правильная перегрузка. Это называется *iterator dispatch*, и работает также хорошо, как и `if constexpr`, несмотря на передачу
лишнего параметра (поскольку параметр — пустая структура, его в реальной жизни никто никуда не передаёт).

### Tag dispatch.
Хорошо, что у итераторов есть теги. А что делать, если тегов нет (например, в массовом деструкторе)? Тогда их можно разве что самим создать:
```c++
struct trivially_destructible_tag {};
struct not_trivially_destructible_tag {};

template <class T>
void destroy_impl(T* first, T* last, trivially_destructible_tag) {}
template <class T>
void destroy_impl(T* first, T* last, not_trivially_destructible_tag) {
	if (!std::is_trivially_destructible_v<T>)
		for (T* p = first; p != last; p++)
			p->~T();
}

template <class T>
void destroy(T* first, T* last) {
	// Хочется как-то выбрать одну структуру-тег из двух на этапе компиляции.
}
```
Как выбрать одну структуру из двух на этапе компиляции? Да тривиально вообще:
```c++
template <bool Cond, typename IfTrue, typename IfFalse>
struct conditional {
	using type = IfFalse;
};
template <typename IfTrue, typename IfFalse>
struct conditional<true, IfTrue, IfFalse> {
	using type = IfTrue;
};

template <class T>
void destroy(T* first, T* last) {
	using tag = typename conditional<is_trivially_destructible_v<T>,
		                            trivially_destructible_tag,
		                            not_trivially_destructible_tag>::type;

	destroy_impl(first, last, tag());
}
```
такое уже есть, и называется `std::conditional`. А `typename std::conditional</*...*/>::type` также сокращается до `std::conditional_t`. . Итого наш пример выглядит так:
```c++
#include <type_traits>

struct trivially_destructible_tag {};
struct not_trivially_destructible_tag {};

template <class T>
void destroy_impl(T* first, T* last, trivially_destructible_tag) {}
template <class T>
void destroy_impl(T* first, T* last, not_trivially_destructible_tag) {
	if (!std::is_trivially_destructible_v<T>)
		for (T* p = first; p != last; p++)
			p->~T();
}

template <class T>
void destroy(T* first, T* last) {
	using tag = std::conditional_t<is_trivially_destructible_v<T>,
	                               trivially_destructible_tag,
	                               not_trivially_destructible_tag>;

	destroy_impl(first, last, tag());
}
```

Такая техника называется *tag-dispatching*, и она, несомненно, работает. Но есть у неё крупная проблема: когда у нас функции были как перегрузки, мы могли свободно добавлять в список перегрузок новые классы с новыми свойствами. А когда мы делаем это `if`'ами (хоть `if constexpr`, хоть `std::conditional_t`), новые классы с новыми свойствами не добавить.

## SFINAE.
Есть другой способ сделать похожее, основанный на поведении компилятора при выведении шаблона?
```c++
template <typename C>
void foo(C&, typename C::iterator); // 1.

template <typename T, size_t N>
void foo(T (&)[N], T*);             // 2.

int main() {
  std::vector<int> v;
  foo(v, v.begin());
  
  int w[10];
  foo(w, w + 2);
}
```
С виду всё хорошо, но давайте разберём, как работает компилятор на таком коде. Сначала производится вывод параметра, а потом — подстановка. В коде выше он видит, что `v` - это `vector&`, а параметр - `C&`, поэтому `C` — это `vector`. Он как бы декомпозирует типы и запускается от частей, а когда доходит до шаблонных параметров, понимает, какой тип здесь имелся в виду.


Из depended имён выводить не можем:
```c++
template <typename T>
struct mytype {
  typedef T type;
};
template <>
struct mytype<int> {
  typedef char type;
};
template <typename T>
void bar(typename mytype<T>::type);
```
Сложность возникла из-за специализаций. Если приходит `char`, то из такого не понятно, откуда он пришёл (могло из `mytype<int>`, а могло из `mytype<char>`), поэтому *deduction* не пытается выводить.

Вернёмся к первому примеру. У нас есть два вызова: от `std::vector` и от C-шного массива. Рассмотрим, что с ними делает компилятор.
1. Когда мы подставляем `vector`, первый шаблон не имеет проблем, а во втором даже параметры шаблона вывести не получается.
2. Когда мы подставляем `int[10]`, в первом шаблоне вывести `C` получается (`C` равно `int[10]`), но возникает ошибка при подстановке — нельзя сделать `int[10]::iterator`.

Но в обоих случаях мы не получаем ошибку компиляции, и дело тут в принципе *SFINAE* — *substitution failure is not an error*: **если в процессе вывода или подстановки шаблона произошла ошибка, это не ошибка компиляции, просто данный шаблон не подходит**.

### `std::enable_if`.
Теперь, вооружившись SFINAE, сделаем так, чтобы наш `destroy` работал без `if`'ов:
```c++
template <bool>
struct enable_if {};
template <>
struct enable_if<true> {
	using type = void;
};

template <class T>
typename enable_if<std::is_trivially_destructible_v<T>>::type // Это возвращаемое значение.
destroy(T* first, T* last) {}
template <class T>
typename enable_if<!std::is_trivially_destructible_v<T>>::type
destroy(T* first, T* last) {
	if (!std::is_trivially_destructible_v<T>)
		for (T* p = first, p != last; p++)
			p->~T();
}
```
Опять же, подобная штука в стандартной библиотеке есть, и называется `std::enable_if`. Для `typename enable_if</*...*/>::type` также создана короткая версия: `std::enable_if_t`.

На практике SFINAE применимо где-нибудь в таком месте:
```c++
template <class T>
struct vector {
	void assign(size_t count, T const& value);

	template <class InputIt>
	void assign(InputIt first, InputIt last);
};

int main() {
	vector<size_t> v;
	v.assign(10, 0); // Выбирается шаблонная перегрузка.
}
```
Исправляется вот так:
```c++
#include <iterator_traits>
#include <type_traits>

template <class T>
struct vector {
	void assign(size_t count, T const& value);

	template <class InputIt>
	std::enable_if_t<
		std::is_base_of_v<
			std::input_iterator_tag,
			std::iterator_traits<InputIt>::category
		>
	> assign(InputIt first, InputIt last);
};

int main() {
	vector<size_t> v;
	v.assign(10, 0);
}
```

## Пара слов о концептах.
SFINAE — это длинно и неудобно, как можно было заметить. И есть вам очень не нравится, в C++20 есть [концепты](./28_concepts.md). Пример выше с их использованием вообще пишется на ура:
```c++
#include <iterator>
template <class T>
struct vector {
	void assign(size_t count, T const& value);

	template <std::input_iterator InputIt>
	void assign(InputIt first, InputIt last);

	/* Также можно вот так:
	template <class InputIt>
		requires std::input_iterator<InputIt>
	void assign(InputIt first, InputIt last);

	После requires можно и что-то более сложное писать. */
};

int main() {
	vector<size_t> v;
	v.assign(10, 0);
}
```
У концептов есть ещё одно преимущество, помимо размера. Когда мы пользуемся SFINAE, нам необходимо перебрать все случаи перегрузок. Если вы в `destroy` написали перегрузку под `std::trivially_destructible`, напишите под `!std::trivially_destructible`. А если вы хотите расширять, будьте добры изменить предикаты. А **концепты умеют понимать, что один концепт расширяет другой**, как с шаблонами. И выбирать наиболее специализированный вариант.