# Сигналы, reentrancy.

- [Запись лекции](https://www.youtube.com/watch?v=_FAWOaT29_w)

---

Давайте представим ситуацию, что у нас есть несколько компонент программы, и когда что-то происходит в одном месте, должно что-то происходить совсем в другом. Например, когда мы в тестовом редакторе тыкаем правую кнопку мыши, у нас появляется контекстное меню (которое к редактору отношения не имеет совершенно). Как бы мы могли это реализовать? Ну, мы могли бы хранить у себя какой-нибудь std::function, и при происхождении какого-то события его вызывать. Обычно такого достаточно, но нем всегда. Например, вашим событием интересуется несколько сущностей. С нажатием ПКМ это вряд ли, но вот если у вас текст в редакторе поменялся, вы можете хотеть сделать несколько действий.

## Сигналы

Сначала разведём немного терминологии. В ситуации, описанной выше события называются **сигналами**, обработчики события — **слотами**, добавление нового обработчика — **connect**'ом, а вызов всех обработчиков — **emit**'ом. Сигналы иногда также называют listeners или observers.

В совсем наивном виде можно делать это так:

```c++
struct signal {
    using slot_t = std::function<void()>;

    signal() = default;

    void connect(slot_t slot) {
        slots.push_back(std::move(slot));
    }

    void operator()() const { // emit
        for (slot t const& slot : slots) {
            slot();
        }
    }

private:
	std::vector<slot_t> slots;  
};
```

Здесь не хватает `disconnect`. Как удалять подписку на событие? `std::function` не умеют сравниваться, чтобы их в `vector`'е искать, да и обязывать пользователя сохранять к себе каждый `std::function`, который он добавляет — такое себе. Поэтому надо создать какую-то структурку, которую пользователь должен будет себе сохранить, и которая будет олицетворять подписку на события. Такая обычно называется `connection`. В ней можно хранить какие-нибудь id или итераторы в связном списке.

Посмотрим на первый подход:

```c++
struct signal {
    using id_t = uint64_t;
    using slot_t = std::function<void()>;

    signal() = default;

    struct connection {
        connection(signal* sig, id_t id)
          : sig(sig), 
        	id(id) {}

        void disconnect() {
            sig->slots.erase(id);
        }

    private:
        signal* sig;
        id_t id;
    }

    connection connect(slot_t slot) {
        next_id++;
        slots.insert({id, std::move(slot)});
        return connection(this, id);
    }

    void operator()() const {
        for (slot_t const& p : slots)
            p.second();
    }

private:
    id_t next_id = 0;
	std::unordered_map<id_t, slot_t> slots;  
};
```

Проблема такой реализации, что она не будет работать такой пример:

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
        conn = global_timer.connect_on_timeout([this] {
            timer_elapsed();
        });
    }
    
    void timer_elapsed() {
        conn.disconnect();
        // Важные действия.
    }

private:
	timer& global_timer;
    connection conn;
};
```

Проблема в том, что при emit'е в цикле мы вызовем `disconnect` и удалим слот, что инвалидирует итератор в range-based `for`'e. Можно пытаться это поправить, заменив collection for на обычный, и делать `*(it++)`. Это поможет от удаления самого себя, но тогда мы не можем отписать другой компонент. Необходимость делать так довольно редка, но всё же встречается (типа вы при сигнале удаляете какой-то компонент, а он подписан на то же событие).

Другой вариант это поправить — превентивно скопировать коллекцию слотов перед вызовами, но если у нас есть какой-то компонент программы, который подписывается при рождении и отписывается от события при смерти, и его кто-то другой при emit'е удалит, то уже мёртвому объекту придёт оповещение.

Как это фиксить? Можно удалять `connection` не сразу, а после прохода по слотам. Можно воспользоваться тем, что `std::function` имеет пустое состояние.

```c++
void operator()() const {
    for (auto i = slots.begin(), i != slots.end(); i++) {
        if (i->second)
            i->second();
    }
    for (auto i = slots.begin(); i != slots.end();) {
        if (i->second)
            ++i;
        else
            i = slots.erase(i);
    }
}
```

Тогда нужно пометить `slots` модификатором `mutable`, так как `operator()` у нас `const`.

Это работает не очень, если emit происходит редко, а disconnect — часто, потому что в таком случае слоты не удаляются нормально.

Поэтому добавим в сигнал поле `mutable bool inside_emit = false;` и модифицируем `operator()` и функцию `disconnect`:

```c++
void operator()() const {
    inside_emit = true;
    for (auto i = slots.begin(), i != slots.end(); i++) {
        if (i->second)
            i->second();
    }
    inside_emit = false;
    for (auto i = slots.begin(); i != slots.end();) {
        if (i->second)
            ++i;
        else
            i = slots.erase(i);
    }
}

void disconnect() {
    auto it = sig->slots.find(id);
    if (sig->inside_emit)
        it->second = slot_t();
    else
        sig->slots.erase(it);
}
```

Теперь проблема в том, что `operator()` получился небезопасным - в случае исключений, не возвращается `inside_emit = false`, поэтому нужно ещё поймать исключение и проставить ему значение `false`, а в `catch`почистить мапу.

Эта реализация уже сильно лучше, но мы можем вызвать `emit` внутри него самого

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

Проблема в том, что внутренний `emit` сделает `erase`, а снаружи мы всё ещё итерируемся по слотам. Одно из решений такой проблемы — сделать вместо флага `inside_emit` счётчик вложенности: `mutable size_t inside_emit = 0`.

Думаете, это всё? Как бы ни так. Есть случай, когда это не будет работать: когда мы при исполнении слота убиваем сигнал целиком. Обычно это происходит, когда мы убиваем не сигнал, а класс, в котором он лежит

```c++
struct user {
    user() = default;
    
    void foo() {
        timer.reset(new::timer(100));
        conn = global_timer.connect_on_timeout([this] {
            timer_elapsed();
        });
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

Одна из вещей, которая это фиксит — та часть данных, которая должна переживать сам класс, хранится отдельно через `shared_ptr`. Второй вариант — поле `mutable bool* destroyed = nullptr;`

```c++
void operator()() const {
	++inside_emit;
	bool* old_destroyed = destroyed;
	bool is_destroyed = false;
	destroyed = &is_destroyed;
	try {
		for (auto it = slots.begin(); it != slots.end(); it++)
			if (*it) {
                (*it)();
				if (is_destroyed) {
					*old_destroyed = true;
					return;
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
    if (destroyed)
        *destroyed = true;
}
void leave_emit() const noexcept {
	--inside_emit;
	if (inside_emit != 0)
		return;
	for (auto it = slots.begin(); it != slots.end();) {
        if (*it)
            ++it;
        else
            ti = slots.erase(it);
	}
}
```

Весь код можно посмотреть [на gist](https://gist.github.com/sorokin/76fde61a9038519ee42b122f05b78dfc).

### Мораль.
- Никогда не пишите *универсальные* сигналы руками. Не надо думать: «А, я сделаю `std::vector<std::function>` и всё будет норм». Нет, не будет. Лучше пользоваться `Boost.Signals`, про них есть [статья на хабре](https://habr.com/ru/post/171471/)
- Когда вы используете сигналы из библиотеки, ознакомьтесь с её документацией. Она может давать не все гарантии. Библиотека может делать копию слотов при `emit`'е, например.
3. Если у вас простой случай, и вы хотите написать простой `signal` чисто под этот случай, то напишите, но поставьте `assert`'ы.

### Реентрабельность.

Семейство проблем, которые мы фиксили, называется **reentrancy**.  Это многозначный термин, в основном объединяющий проблемы с глобальными или статичными данными. Программа в целом или её отдельная процедура называется реентераабельной, если она разработана таким образом, что одна и та же копия инструкций программы в памяти может быть совместно использована несколькими пользователями или процессами. Например, написанный выше `signal` — реентерабельный.
