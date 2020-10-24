# Сигналы, reentrancy, стратегии обработки ошибок

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

Замечание: семейство проблем, которые мы фиксили, называется *reentrancy*.  Это многозначный термин, в основном объединяющий проблемы с глобальными или статичными данными. Программа в целом или её отдельная процедура называется реентераабельной, если она разработана таким образом, что одна и та же копия инструкций программы в памяти может быть совместно использована несколькими пользователями или процессами. Например, написанный выше `signal` - реентерабельный.