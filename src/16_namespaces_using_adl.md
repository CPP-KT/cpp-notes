# Пространства имён, using-декларации, using-директивы, ADL.
- [Запись лекции №1](https://youtu.be/mU06WPxCxHk?si=k1Cc3duiYuLQn1Qx)
---
## Пространства имён.
В Си в библиотеках у функций обычно есть префикс названия библиотеки, префикс раздела и ещё бесконечное количество префиксов. Например, библиотека cairo для работы с векторной графикой имеет имена по типу `cairo_mesh_pattern_move_to`. Эту функцию нельзя назвать просто `move_to`, потому что в другой библиотеке тоже может быть `move_to`, имеющий отношение к совершенно другим вещам, а коллизии имён вы не хотите.

В C++ для предотвращения такого используются пространства имён:
```c++
namespace cairo {
	namespace mesh {
		namespace pattern {
			void move_to();
		}
	}
}
namespace cairo { // Одно пространство имён можно открывать несколько раз. Они сольются в одно.
	namespace mesh {
		namespace pattern {
			void curve_to();
		}
	}
}

int main() {
	cairo::mesh::pattern::move_to();
	cairo::mesh::pattern::curve_to();
}
```
А что мы выигрываем от такого? Теперь вместо одного символа (`_`) у нас два (`::`). А выигрываем мы то, что находясь внутри пространства имён, мы можем вызывать свои функции без этих длинных префиксов:
```c++
namespace cairo {
	namespace mesh {
		namespace pattern {
			void curve_to();

			void test() {
				curve_to();
			}
		}

		void test() {
			pattern::curve_to();
		}
	}

	void test() {
		mesh::pattern::curve_to();
	}
}

void test() {
	cairo::mesh::pattern::curve_to();
}
```
Кстати, если вам интересно, чем отличаются функции `test` с точки зрения линковщика, то **в имена декорированных символов просто вписываются особым образом эти самые пространства имён**.

Всё что мы пишем вне любых пространств имён, считается лежащим в «*глобальном пространстве имён*». Чтобы обратиться явно к чему-то в нём, напишите перед именем двойное двоеточие.

## Способы не писать длинные названия извне.
Первый — *namespace alias*. Есть в стандартной библиотеке пространство имён `std::filesystem`. Если мы не хотим писать долгое имя класса `std::filesystem::path`, мы пишем `namespace fs = std::filesystem`, и теперь можем писать `fs::path`.
Второй:
### Using-декларация.
```c++
namespace ns {
	void foo(int);
}

int main() {
	using ns:foo; // Можно делать декларацию всего, кроме других пространств имён.

	foo();
}
```
Using-декларация берёт сущность, на которую ссылаемся и как бы объявляет её ещё раз там, где вы находитесь. В частности, если вы напишете её в другом пространстве имён, она останется там:
```c++
#include <filesystem>
namespace f {
	using std::filesystem::path;

	path p; // Корректно.
}
path p;     // Некорректно.
f::path p;  // Корректно.
```
При этом делать объявление двух сущностей с одним именем всё ещё нельзя:
```c++
namespace n {
	struct bar {};
}

struct bar {};
using n::bar; // Ошибка компиляции, два объекта с именем `bar`.
```
Для перегрузок функций всё работает как надо:
```c++
namespace n {
	void foo(int);
}
namespace m {
	void foo(float);
}

void foo(char);

int main() {
	using n::foo;
	using m::foo;
	foo(42.0f); // m::foo.
	foo(42);    // n::foo.
	foo('*');   //  ::foo.
}
```
Using-декларацию можно применять не только для пространств имён, но и для классов.
```c++
struct base1 {
	void foo(int);
};
struct base2 {
	void foo(float);
};
struct derived : base1, base2 {
	using base1::foo;
	using base2::foo;
};
int main() {
	derived d;
	d.foo(42); // Без `using` не делается overload resolution и будет ошибка, так как два кандидата из разных баз.
}
```
Ещё можно применить так:
```c++
struct base {
	void foo(int);
};
struct derived : private base {
	using base::foo; // Без `using` не работает, потому что `private`.
};
int main() {
	derived d;
	d.foo(42);
}
```
Аналогично можно и с конструкторами:
```c++
struct my_error : std::runtime_error {
	using runtime_error::runtime_error;
};
```

### Using-директива.
Можно подключать полностью всё пространство имён: `using namespace somelib;`. По сути, оно говорит при поиске в неймспейсе, где она написана, также искать в неймспейсе `somelib`. Using-декларация и using-директива немного отличаются:

```c++
namespace n1 {
	class mytype {};
	void foo();
}
namespace n2 {
	class mytype {};
	void bar();
}

using n1::mytype;
using n2::mytype;   // Ошибка.

using namespace n1;
using namespace n2; // Нет ошибки.
mytype a;           // Ошибка: "mytype is ambiguous".
```
**using-директива не декларирует ничего, а просто помечает, что в текущем пространстве имён используется другое**. И компилятор просто берёт, и всегда когда ищет что-то в одном пространстве имён, также ищет это и во втором. Это даёт такого рода эффекты:
```c++
namespace n {}

using namespace n;

namespace n {
	class mytype {};
}

mytype a;
```
Такая штука вполне компилируется и делает то, что вы предполагаете. Понятно, что на той же строке вместо `using namespace n` написать `using n::mytype` нельзя.

## [Unqualified name lookup](https://en.cppreference.com/w/cpp/language/unqualified_lookup).

*Unqualified name lookup* — это когда вы ищете просто имя или то, что слева от `::`. То есть когда вы ищете `foo::bar`, `foo` ищется при помощи unqualified name lookup, а `bar` — [qualified name lookup](https://en.cppreference.com/w/cpp/language/qualified_lookup).\
Unqualified name lookup по вызову функций и операторов имеет особые правила ([argument-dependent lookup](#ADL)).

Глобально мы тупо идём вверх по пространствам, и когда нашли имя, останавливаемся. Если нашли два, то ambiguous. `using`'и с этим взаимодействуют так:
- using-декларация находится там, где написана.
- using-директива считается объявленной в ближайшем пространстве имён, которое окаймляет текущее и то, которое подключаем.
```c++
namespace n1 {
	int const foo = 1;
}
namespace n2 {
	int const foo = 2;

	namespace n2_nested {
		using n1::foo;

		int test() {
			// Ищем в n2::n2_nested::test.
			// Не находим, идём выше.

			return foo; // n1::foo
		}

		// Ищем в n2::n2_nested.
		// Находим, останавливаемся.
	}
}
```
```c++
namespace n1 {
	int const foo = 1;
}

// Считается, что n1::foo для using-директивы объявлено тут.

namespace n2 {
	int const foo = 2;

	namespace n2_nested {
		using namespace n1;

		int test() {
			return foo; // n2::foo.
		}
	}
}
```
Отсюда вот такой пример не компилируется:
```c++
namespace n1 {
	int const foo = 1;
}

int const foo = 100;

namespace n2 {
	namespace n2_nested {
		using namespace n1;

		int test() {
			return foo; // n1::foo и ::foo видны на одном уровне, ambiguous.
		}
	}
}
```

**using-директивы транзитивны**, то есть когда вы делаете using-директиву пространства имён с другой using-директивой, то подключили вы два, а не одно пространство имён.

```c++
namespace n2 {};

namespace n1 {
	struct foo {};
	using namespace n2;
}
namespace n2 {
	struct foo {};
	using namespace n1;
}

using namespace n1;
// У нас транзитивно появляется using namespace n2;

int main() {
	foo a; // В глобальном пространстве имён видно n1::foo и n2::foo, ambiguous.
	n1::foo a; // Qualified lookup ищет сначала в самом пространстве, потом в inline-namespace'ах, и уже в конце идёт по using-директивам.
	           // Впрочем, про QNL лучше почитайте cppreference по ссылке выше, а мы тут UNL обсуждаем.
}
```

Когда пишем using и alias в хедерах, то они работают везде, куда include'ят этот хедер, что мы редко хотим, поэтому есть такое правило: **в заголовочных файлах using-директивы и -декларации не писать**, так как почти никогда не хотим использовать их для пользователя.

### ADL.
Как было сказано выше, для функций unqualified name lookup имеет особые правила. Вот они:
```c++
namespace my_lib {
	struct big_integer {};
	big_integer operator+(big_integer const&, big_integer const&);
	void swap(big_integer&, big_integer&);
}

int main() {
	my_lib::big_integer a;
	a + a;
	swap(a, a);
}
```
Казалось бы, оператор `+` не должен находиться, как и `swap`. Если бы это работало так, то пришлось бы везде писать `my_lib::operator+` или делать `using`.

Поэтому есть правило, которое называется [*argument-depended lookup*](https://en.cppreference.com/w/cpp/language/adl). Когда мы вызываем функцию, она ищется не как описано выше, а учитывает типы параметров. Точнее, смотрит в то пространство имён, где написаны аргументы оператора. **Для каждого аргумента производится поиск в его пространстве имён (и пространствах имён всех его баз)**. Причём только в пространстве имён, не выше.

Немного best practices о том, как надо делать `swap`:
```c++
template <class T>
void foo(T a, T b) {
	// ...
	using std::swap;
	swap(a, b);
	// ...
}
```
Теперь у нас получается шаблонный `std::swap` и, возможно, есть не-шаблонный ADL.
- Если есть ADL, выбирается он, потому что из шаблонного и не-шаблонного выбирается второй.
- Если нет ADL, то есть только `std::swap`, и он вызывается.

Если не сделать `using std::swap`, то функция не будет работать для, скажем, `int`'ов.\
В контексте шаблонов надо сказать, что **ADL работает на этапе подстановки шаблона, в то время как поиск имени по дереву вверх — на этапе парсинга**.


## Безымянные пространства имён.
На лекции про компиляцию мы обсуждали модификатор `static` для функций и переменных.
```c++
static void foo() {}
```
Такой `static` делал функции локальными для единицы трансляции. Но есть проблема с классами. Они же не генерируют код в C. Но в C++ они (из-за наличия специальных функций-членов класса) его генерируют. Если у нас есть два нетривиально-разрушаемых типа `mytype` в разных единицах трансляции, будет конфликт деструкторов. Более того, тут есть
ещё более интересный пример:
```c++
// a.cpp
struct my_type {
	int a;
};
void foo() {
	std::vector<mytype> v;
	v.push_back(/*...*/);
}
```
```c++
// b.cpp
struct my_type {
	int a, b;
};
void bar() {
	std::vector<mytype> v;
	v.push_back(/*...*/);
}
```
Тут сами классы тривиально делают вообще всё (создаются, копируются и разрушаются), значит с ними нет нарушения. Но есть нарушение ODR в `std::vector<mytype>::push_back`, он делает разные вещи для разных `mytype`.\
Поэтому по стандарту разных объявлений классов с одинаковыми именами быть не должно. 

Чтобы такого не происходило, существуют безымянные пространства имён;
```c++
namespace {
	struct my_type {
		int a;
	};
}
```
По определению это равносильно
```c++
namespace some_unique_identifier {
	struct my_type {
		int a;
	};
}

using namespace some_unique_identifier;
```
Несложно заметить, что тут происходит именно то, что мы хотим. Аналогично, как видно, можно делать для функций и для переменных, а вообще не делать `static`. В общем, это нужно, чтобы делать сущности локальными.

Анонимные пространства имён даже лучше:
```c++
template <int*>
struct foo {};

static int x, y;

int main() {
	foo<&x> a;
	foo<&y> b;
}
```
В C++03 это не работает, потому что `x` — не уникальное имя. А это проблема, поскольку `foo<&x>` — это декорированное имя `foo`, в который встроили адрес переменной `x`. А когда мы имеем `static`, из-за не уникальности сочетания токенов `&x` в разных единицах трансляции, уникально задекорировать `foo<&x>` не получится.

Итак, `static` сделали deprecated в C++03, но в C++11 сказали, что если человек пишет «`static`», он имеет в виду безымянное пространство имён.

## Ещё немного про `static`.
```c++
static void foo();     // Локальный для единицы трансляции, обсуждали.
struct foo {
	static void bar(); // Нет параметра `*this`, можно вызывать `foo:bar()`.
	static int a;      // Как глобальная переменная, но с именем `foo:a`, хранится не в каждом экземпляре типа.
};
int foo() {
	static int x = 0; // Создаётся при первом заходе в функцию, живёт до конца программы
	return ++x;
}
// По сути `foo` считает, сколько раз её вызвали.
```
Можно словить рекурсивную инициализацию, это UB, какие-то компиляторы выдают исключение, какие-то зацикливаются, какие-то выдают 0:
```c++
int& f();
int g() {
	return f()
}
int& f() {
	static int x = g();
	return x;
}
int main() {
	f();
}
```
