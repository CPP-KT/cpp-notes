# optional, variant, tuple, string_view

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

Проблема такого кода - две переменных, связь которых не очень очевидна, если они будут в составе какоого-нибудь большого класса. Если это не очевидно для компилятора, то будет плохо оптимизациям.

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

Разыменование пустого `optional` это UB, но метод `value` бросается исключение.

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

template <bool TriviallyDestructible>
struct optional_base {
    ~optional_base() {
        /// ...
    }
};

template <>
struct optional_base<true> : optional_storage<T> {  
};

template <typename T>
struct optional: optional_storage<T, std::is_trivially_destructible<T>> {  
    // ...
};
```

Примерно так это и реализована в стандартной библииотеке, хоть и получается, что на каждую тривиальность по базовому классу.

## variant

Предположим, что мы хотим хранить в `deffered_value` либо посчитанное значение, либо функцию, которая может его посчитать. Когда значение уже посчитано, хранить функцию нам не нужно. Такое можно было бы оптимизировать с помощью `union`. Для этого в стандартной библиотеке уже есть класс `std::variant`. 

```c++
int main() {
    std::variant<A, B, C> v;
    
}
```

