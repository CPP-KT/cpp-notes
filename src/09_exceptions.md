# Исключения, гарантии безопасности исключений, RAII
- [Запись лекции №1](https://www.youtube.com/watch?v=R0tVZ1px5-Q)
- [Запись лекции №2](https://www.youtube.com/watch?v=8PpW8qS2tEg)
---
```c++
bool do_something() {
	FILE* file = fopen("1.txt");
	if (!file)
		return false;
	size_t bytes_read = fread(..., file);
	if (bytes_read < 0)
		return false;
	bytes_read = fread(..., file);
	if (bytes_read < 0)
		return false;
	bytes_read = fread(..., file);
	if (bytes_read < 0)
		return false;
	fclose(file);
	return true;
}
```
Как можно возвращать ошибку? Можно это делать с помощью error-кодов (так делали в Си), но это не очень удобно. Для этого используют механизм исключений.

```c++
void f() {
	if (...)
		throw runtime_error const& e("...");
}
```

Что происходит при бросании исключения: 

- Создаётся копия объекта, переданного в `throw`. Копия будет существовать, пока исключение не будет обработано. Если тип объекта имеет конструктор копирования, то будет использован он.

- Прерывается исполнение программы.
- Выполняется раскрутка стека, пока исключение не будет обработано (поймано), вызываются деструкторы в правильном порядке.

Чтобы ловить исключения, есть конструкция `try`-`catch`:

```c++
try {
	...
	f();
	...
} catch (runtime_error const& e) {
	...
}
```

Выполняется сначала блок `try` если в нем ничего не произошло, код продолжает выполняться. Если ловится какой-то exception, то он переходит в соответствующий `catch` блок. Если такового нет, то исключение вылетает за пределы `try-catch`. Ловить в `catch` можно и любые исключения `catch(...)`

## Пример:

```c++
struct base {
	virtual std::string msg() const {
		return "base";
	}
}
struct derived : base {
	std::string msg() const {
		return "derived";
	}
}
int main() {
	try {
		throw derived(); // без const& в catch выведет base
          throw new derived(); // вот так писать не надо, бросится указатель
	} catch (base const& e) {
		std::cout << e.msg();
          throw e; // вот так тоже не очень, он пробрасывает со статическим типом (base)
	}
}
```

## Ошибки и аллокация памяти

`operator new` и `operator delete` - работают как `malloc` и `free` (выделяют сырую память), но бросают исключения, а не возвращают `nullptr`

Посмотрим на такой пример:

```c++
my_string& my_string::operator =(char const* rhs) {
     char* old_data = data_;
     size_ = strlen(rhs);
     capacity_ = size_;
     data_ = (char*)operator new(size_ + 1);
     memcpy(data_, rhs, size_ + 1);
     operator delete(old_data);
     return *this;
}
```

Если `operator new` выкинет исключение, то получим проблему, что мы уже изменили `size_` и `capacity_`, но ничего не скопировали.

## Про работу с ресурсами и RAII

Посмотрим на такой код:


```c++
int main() {
     FILE* a = my_fopen("a.txt", "r");
     ...
     fclose(a);
}
```

Чем это плохо? Нам нужно не забывать закрывать ресурс. Особенно возникают проблемы, если в процессе кидаем исключения, а ресурсов несколько.

Здесь придерживаются идиомы `RAII` - resource allocation is initialization

```c++
struct file {	
     file(char const* filename, char const* mode) : f(my_fopen(filename, mode)){}
     file(file const&) = delete;
     file& operator=(file const&) = delete;
     ~file() {
          fclose(f);
     }
     FILE* f;
};
```

Тогда ресурсы проще создавать и не будет проблем с закрытием при исключениях:

```c++
int main() {
     file a("a.txt", "r");
}
```

В стандартной библиотеке есть похожий класс - **unique_ptr**. Он представляет из себя уникальный указатель на объект, который нельзя копировать. При уничтожении указателя автоматически вызывается деструктор объекта, на который он указывает. 

Обычно его создают через `make_unique`:

```c++
std::unique_ptr<file> a = std::make_unique<file>("a.txt", "r");
```

Через `.get()` можно получить указатель из `unique_ptr`:

```c++
file* ptr = a.get();
```

## Гарантии исключений

1. `nothrow` - гарантируется, что исключение не будет выброшено наружу

2. `strong` - допускается проброс исключений, однако гарантируется сохранение всего исходного состояния в случае исключения
3. `basic` - допускается изменение состояния, однако сохраняется ивариант, утечки ресурсов не допускаются
4. `no guarantee`

В деструкторах лучше не делать исключения, это может вызывать проблемы, если мы бросили исключение, вызвался другой деструктор, который тоже бросил исключение. 

### Swap trick

Хорошая идея - писать операторы присваивания и копирования через `swap`. Это даёт нам `strong` гарантии:

```c++
my_string& my_string::operator=(my_string rhs) {
     swap(rhs); 
     return *this;
}
```

Здесь при передаче вызовется оператор копирования строки, а потом мы сделаем swap.

Ещё пример:

```c++
void erase_middle_basic(std::vector<std::string>& v) {
     v.erase(v.begin() + v.size() / 2);
}
void erase_middle_strong(std::vector<std::string>& v) {
     std::vector<std::string> copy = v;
     erase_middle_basic(copy);
     std::swap(v, copy);
}
```

