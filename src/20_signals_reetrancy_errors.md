# Сигналы, reentrancy, стратегии обработки ошибок

- [Запись лекции №1](https://www.youtube.com/watch?v=_FAWOaT29_w)
- [Запись лекции №2](https://www.youtube.com/watch?v=l3QRAy1jv2Y)
## Сигналы

**Сигналы** - механизм "подписки" нескольких функций на события в другой. Иногда их называют listeners или observers.

В совсем наивном виде можно делать это так:

```c++
struct signal {
    using slot_t = std::function<void()>;
    signal();
    void connect(slot_t slot) {
        slots.push_back(std::move(slot));
    }
    void operator()() const {
        for (slot t const& slot : slots) {
            slot();
        }
    }
  private:
	std::vector<std::function<void()>> slots;  
};
```

Как удалять подписку на событие? Есть два подхода: возвращать `id` или использовать `linked_list`.

Посмотрим на первый:

```c++
struct signal {
    using id_t = uint64_t;
    using slot_t = std::function<void()>;
    signal();
    struct connection {
        connection(signal* sig, id_t id)
          : sig(sig), 
        	id(id) {}
        void disconnect() {
            sig->slots.erase(id);
        }
      private:
        signal* sig;
        id_it id;
    }
    connection connect(slot_t slot) {
        next_id++;
        slots.insert({id, std::move(slot)});
        return connection(this, id);
    }
    void operator()() const {
        for (slot t const& p : slots) {
            p.second();
        }
    }
  private:
    id_t next_id = 0;
	std::unordered_map<id_t, slot_t> slots;  
};
```

Проблема такой реализации, что не будет работать такой пример:

```c++
struct timer {
    timer(unsigned timeout);
    signal::connection connect_on_timeout(signal::slot_t slot) {
        return on_timeout.connect(slot);
    }
  private:
    signal on_timeout;
};

struct user {
    user(timer& global_timer) 
        : global_timer(global_timer) {}
    
    void foo() {
        conn = global_timer.connect_on_timeout([this] {timer_elapsed()});
    }
    
    void timer_elapsed() {
        conn.disconnect();
        // ...
    }
  private:
	timer& global_timer;
    connection conn;
};
```

Проблема в том, что в `operator()` в цикле мы вызовем `disconnect` и удалим слот, что инвалидирует итератор в range-based for'e.

Как это фиксить? Можно удалять `disconnected` не сразу, а после прохода по мапе. Можно воспользоваться тем, что `std::function` имеет пустое состояние.

```c++
void operator()() const {
    for (auto i = slots.begin(), i != slots.end; ++i) {
        if (i->second) {
            i->second();
        }
    }
    for (auto i = slots.begin(); i != slots.end;) {
        if (i->second) {
            ++i;
        } else {
            i = slots.erase(i);
        }
    }
}
```

Тогда нужно пометить `slots` модификатором `mutable`, так как `operator()` у нас `const`.

Чтобы `map` чистился не только если вызывается `operator()` , добавим поле `mutable bool inside_emit = false;` и модифицируем `operator()` и функцию `disconnect`:

```c++
void operator()() const {
    inside_emit = true;
    for (auto i = slots.begin(), i != slots.end; ++i) {
        if (i->second) {
            i->second();
        }
    }
    inside_emit = false;
    for (auto i = slots.begin(); i != slots.end;) {
        if (i->second) {
            ++i;
        } else {
            i = slots.erase(i);
        }
    }
}

void disconnect() {
    auto it = sig->slots.find(id);
    if (sig->inside_emit) {
        it->second = slot_t();
    } else {
        sig->slots.erase(it);
    }
}
```

Теперь проблема в том, что `operator()` получился небезопасным - в случае исключений, не возвращается `inside_emit = false`, поэтому нужно ещё поймать исключение и проставить ему значение `false`, а в `catch`почистить мапу.

Такая реализация близка к тому, что нужно в 95% случаев, но есть случай, когда это не будет работать. Если в примере выше таймер не был глобальным, а был заведён нами:

```c++
struct user {
    user() = default;
    
    void foo() {
        timer.reset(new::timer(100));
        conn = global_timer.connect_on_timeout([this] {timer_elapsed()});
    }
    
    void timer_elapsed() {
        timer.reset();
    }
  private:
	std::unique_ptr<timer> timer;
    connection conn;
};
```

В `time_elapsed()` удаляем таймер, но внутри таймера был `signal`, который тоже удалится.

Ещё одна проблема - рекурсивные вызовы.

```c++
// emit
//     slot1
//     slot2
//     slot3
//         ...
//             emit
//                 slot1
//                 slot2
//                 slot3
//                 slot4
//                 slot5
//                 leave_emit
//                     erase
//     slot4
//     slot5
//     leave_emit
```

Проблема в том, что внутренний `emit` сделает `erase`, а снаружи мы всё ещё итерируемся по слотам. Одно из решений такой проблемы - сделать счётчик `mutable size_t inside_emit = 0`. 

Осталась проблема с тем, когда `signal` удаляется. Одна из вещей, которая это фиксит - та часть данных, которая должна переживать сам класс, хранится отдельно через `shared_ptr`. Второй вариант - поле `mutable bool* destroyed = nullptr;`

```c++
void operator()() const {
	++inside_emit;
	bool* old_destroyed = destroyed;
	bool is_destroyed = false;
	destroyed = &is_destroyed;
	try {
		for (auto i = slots.begin(); i != slots.end(); ++i) {
			if (*i) {
                (*i)();
				if (is_destroyed) {
					*old_destroyed = true;
					return;
				}
			}
        }
	} catch (...) {
		destroyed = old_destroyed;
		leave_emit();
        throw;
    }
	destroyed = old_destroyed;
	leave_emit();
}
~signal() {
    if (destroyed) {
        *destroyed = true;
    }
}
void leave_emit() const noexcept {
	--inside_emit;
	if (inside_emit != 0)
		return;
	for (auto i = slots.begin(); i != slots.end();) {
        if (*i) {
            ++i;
        } else {
            i = slots.erase(i);
        }
	}
}
```

Весь код можно посмотреть [на gist](https://gist.github.com/sorokin/76fde61a9038519ee42b122f05b78dfc).

Как можно заметить, писать свои сигналы (а особенно читать) - не самая тривиальная задача. Поэтому, на самом деле, лучше пользоваться `Boost.Signals`, про них есть [статья на хабре](https://habr.com/ru/post/171471/). Если пользуетесь сигналами из библиотек, то нужно внимательно проверять гарантии, например, на удаления и рекурсивные emit'ы.

*Замечание:* семейство проблем, которые мы фиксили, называется *reentrancy*.  Это многозначный термин, в основном объединяющий проблемы с глобальными или статичными данными. Программа в целом или её отдельная процедура называется реентераабельной, если она разработана таким образом, что одна и та же копия инструкций программы в памяти может быть совместно использована несколькими пользователями или процессами. Например, написанный выше `signal` - реентерабельный.

## Стратеги обработки ошибок

Часто встречаются ошибки нескольких видов:

- hardware errors
- compilation errors
- runtime errors

Предположим, что есть функция, которая ожидает, что массив на входе отсортирован. 

```c++
int binary_search(...) {
    if (!is_sorted(...)) {
        throw std::runtime_error("");
    }
}
```

Делать так не очень полезно, так как проверка на отсортированность асимптотически занимает больше времени, чем сам алгоритм. Возможно, мы хотим проверку, которую можно уметь отключать (например, если код собирается в релизе, убрать проверки). Кроме того, `throw` в коде выше тоже под вопросом - как вызывающая сторона должна реагировать на такое исключение? Вместо него лучше использоваться `std::abort`.

В сишной библиотеке есть специальный макрос `assert`, который проверяет свой аргумент, и если он `false`, то вызывается `std::abort`. Кроме того, так как это макрос, то его можно включать и отключать. Например, включать только в DEBUG.

С помощью  `assert` можно проверять только какие-то внутренние свойства программы, это можно назвать *internal consistency errors*, а не ситуации типа "файл не открылся", которые, на самом деле, являются не ошибками, а *rare/exceptional situations*.

### Как можно обрабатывать внутренние ошибки?

- Игнорировать
- abort программы
- Сообщить вызывающей стороне
- Логгировать такие ошибки и продолжать работу

Хоть вариант игнорирования и кажется глупым, на самом деле, часто на практике получается именно так, как минимум, из-за того, что некоторые ситуации тяжело предположить и обработать.

Abort программы тоже спорный подход. С одной стороны, это плохо, когда программа завершается, например, из-за ошибки в библиотеке, которая не очень важная для остальной части программы. Но аргумент за abort - "а что вместо него?".

Сообщение вызывающей стороне - это исключения или возврат кодов ошибок. Проблема бросания исключений в том, что код, через который оно пролетает, ломается. Поэтому часто, если библиотека бросает исключение при какой-то внутренней ошибке, то усложняется весь код по пути пробрасывания исключения, так как он должен стать exception-безопасным (например, как мы писали в векторе и прочем).  

Логирование - неплохая стратегия, так видно как ошибку (в отличие от игнорирования), так и то, как программа вела себя, если бы она игнорировалась.

Забавный аргумент - если ошибка делает abort программы, то на такую ошибку обращают внимание и бегут чинить её, в отличие от логов, которые могут игнорировать разработчики. Часто подход к обработке ошибок различный у разработчиков с разным бэкграундом и зависит от применений.

### Обработка редких/исключительных ситуаций

Чаще всего такие ошибки сообщаются вызывающей стороне, но в некоторых случаях такое не работает. Пример такого случая - исключение, если бы оно произошло в вызове слота в `signal`. Должны ли после исключения вызываться оставшиеся слоты? Должно ли оно пробрасываться наверх? Если оно пробрасывается в вызывающую сторону, то не понятно, от какого из слотов оно.  На самом деле, стратегия report to caller имеет смысл только в том случае, когда вызывающая сторона "заинтересована в успехе операции", чем не является случай с сигналом, поэтому если в слоте происходит ошибка, то он должен сам её поймать и сделать что-то разумное. 

Имеет ли смысл для таких ситуаций abort? Пример такого - случай нехватки памяти, который не понятно, как разумно обработать. Ещё один пример - ошибка открытия файла, который является внутренней частью программы (например, какой-нибудь конфиг).