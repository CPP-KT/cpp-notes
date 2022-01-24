# Корутины

- [Запись лекции №1](https://youtu.be/IjI6lDLZ5w0)
- [Запись лекции №2 (до 46 минуты)](https://youtu.be/5zszqIm4Cyk)

## Пример
```
socket
    recv
    send

    on_recv_ready
    on_send_ready
```
Хотим реализовать echo-сервер: нам приходит сообщение и мы посылаем его же
обратно отправителю.
```c++
socket& s;
...
// inside message loop
s.on_recv_ready([&] {
    char buf[1000];
    size_t transf = s.recv(buf);
    s.send(buf, buf + transf);
});
```
Проблемы решения: может не хватить места для сообщения, и ещё много всего (нужно
дополнить).

Сделаем вспомогательную функцию, которую мы вызываем если считаем что сокет
можно читать (`do_recv`) и ещё одну такую же для записи (`do_send`):
```c++
void do_recv() {
    assert(buf_data_start < buf_data_end);
    buf_data_end = recv(buf, BUF_SIZE);
    buf_data_start = 0;
    do_send();
    on_recv_ready([] () {});
    on_send_ready(do_send);
}

void do_send() {
    buf_data_start += s.send(buf + buf_data_start, buf_data_end - buf_data_start);
    if (buf_data_start == buf_data_end) {
        on_send_ready([](){});
        on_recv_ready(do_recv);
    }
}

...

socket& s;
char buf[BUF_SIZE];
size_t buf_data_start, buf_data_end;
while (true) {
    on_recv_ready(do_recv);
}
```
Примерно такое API есть в [QT](https://doc.qt.io/qt-5/qabstractsocket.html) и
других библиотеках.

Ещё один способ реализовывать подобные API (как это сделано в
boost.asio):
```c++`
async_read_some(buffer, [](){
    // здесь пишут, что нужно сделать после получения
    ...
});

async_write_some(buffer, [](){
    // то же самое
    ...
});
```
Этот паттерн называют *proactor*, а другой способ (как в QT) - *reactor*.

Но писать всё это очень муторно, научимся делать подобные вещи более просто.

## Корутины
"A coroutine is a function that can suspend execution to be resumed later" (c)
cppref
- [CppCon2015 C++ Coroutines](https://github.com/CppCon/CppCon2015/tree/master/Presentations/C%2B%2B%20Coroutines)
- [Пример ручной смены контекста в корутине](https://github.com/sorokin/coroutines)

В презентации приводится пример более простого сервера и его реализация без
корутин/с корутинами - в последнем случае получается очень коротко.

Как реализовать корутины без поддержки компилятора? Ну во-первых, где-то нужно
хранить её локальные переменные. Можно завести дополнительный стек - такой
подход называется *stackful*. Можно попушить все регистры и верхушку стека, в
которых хранятся переменные, но тогда мы не сможем зайти больше чем на один
уровень рекурсии в корутине - это *stackless* подход.

Видно, что для стекфул корутин меньше ограничений и не нужно явно указывать
`await` (т.к. тебя можно спокойно запаузить в любой момент - фрейм не
повредится).

В стандарте корутины не получили поддеркжу со стороны библиотеки, поэтому нужно
либо использовать сторонние библиотеки либо самим реализовывать примитивы. Один
пример библиотеки - [cppcoro](https://github.com/lewissbaker/cppcoro).

## Стандартная реализация
- [C++ Coroutines under the covers](https://www.youtube.com/watch?v=8C8NnE1Dg4A)

Было два способа реализовать корутины: сделать структуру с методами для
паузы/резьюма, либо применить type erasure (чтобы что? Надо дополнить) - выбрали
последний (я не понял чем это отличается от структуры). В
[презентации](https://github.com/CppCon/CppCon2016/tree/master/Presentations/C%2B%2B%20Coroutines%20-%20Under%20The%20Covers)
есть картинка, на которой изображена примерная схема сгенерированной структуры
для фрейма корутины, что-то такое:
```c++
struct f.frame {
    FnPtr ResumeFn;
    FnPtr DestroyFn;
    int suspend_index;
    int i;
};

void f.destroy(f.frame* frame) {
    free(frame);
}

void f.cleanup(f.frame* frame) {}

void f.resume(f.frame* frame) {
    ... // переходим к очередной инструкци корутины
}

void* f(int *n) {
    ...
}
```
(было бы хорошо переписать весь код со слайда)

Ну и ещё одна фича стандартных корутин в том, что они выделяют свой фрейм на
хипе (а если повезёт с оптимизациями, то на стеке, например через `alloca`)

## Кастомные корутины
Если вдруг нам не подошла корутина из cppcoro, можем попробовать реализовать её
сами. Характеристики корутин (что мы могли бы определить сами (каво)):
1. Coroutine type (`task`, `generator`, `async_generator`, etc.)
2. Awaitable - операции, которые могут работать подолгу (`read`, `sleep`, etc.)
3. Coroutine frame - фрейм сгенерированный компилятором
4. Promise type - дополнительные данные помимо фрейма (хранятся в структуре
   фрейма).
5. Coroutine handle - держит указатель на type erase-нутый фрейм корутины в
   хипе; содержит в себе функцию `resume`.

Какие из этих точек кастомизации предоставляют компиляторы?
Посмотрим на `co_await x;` - нам нужно остановить корутину и сделать какую-то
свою операцию для `x`. Для этого компиляторы генерируют подобный код
```c++
x.await_suspend(handle);  // передаёт указатель на фрейм
---<suspend>----
```
Т.е. мы должны в `await_suspend` сделать что мы хотели а затем, в конце, вызвать
`resume` от фрейма. Ещё, для awaitable-ов делается проверка на то, нужно ли их
суспендить, т.е. сгенеренный код примерно такой:
```c++
if (!x.await_ready()) {
    x.await_suspend(handle);  // передаёт указатель на фрейм
    ---<suspend>----
}
```
Иногда после ожидания мы хотим получить какой-то результат, как тут:
```c++
size_t transfered = co_await recv(buf, 1000);
```
Для этого компилятор генерит ещё кусочек кода:
```c++
if (!x.await_ready()) {
    x.await_suspend(handle);  // передаёт указатель на фрейм
    ---<suspend>----
}
// await_resume не обазательно делать после await_suspend, просто такое
// название
<result of await> = x.await_resume();
```
Можно заметить, что для того чтобы написать свой awaitable, нам ничего не нужно
знать про тип корутины.

## Свои корутины
Используя эти знания, можем написать два awaitable: `await_never` (никогда не
делает suspend), `suspend_always` (никогда не ready, в suspend ничего не делает,
в resume тоже ничего не делает).

```c++
#include <coroutine>
#include <iostream>

struct task {
    struct promise_type {
        // Четыре обязательные функции:
        task get_return_object() noexcept {
            return task{std::coroutine_handle<promise_type>::from_promise(*this);
        }

        std::suspend_always initial_suspend() noexcept{
            return std::suspend_always{};
        }

        std::suspend_always final_suspend() noexcept {
            return std::suspend_always{};
        }

        void unhandeled_exception() noexcept {}
    };

    std::coroutine_handle<promise_type> handle;
};

task foo() {
    std::cout << "in foo 1\n";
    co_await std::suspend_always{};
    std::cout << "in foo 2\n";
    co_await std::suspend_always{};
    std::cout << "in foo 3\n";
    co_await std::suspend_always{};
    std::cout << "in foo 4\n";
}

int main() {
    task t = foo();
    std::cout << "in main 1\n";
    t.handle.resume();
    std::cout << "in main 2\n";
    t.handle.resume();
    std::cout << "in main 3\n";
    t.handle.resume();
    std::cout << "in main 4\n";
    t.handle.resume();
    return 0;
}
```
Этот код не совсем корректен, потому что мы не деаллоцировали наш фрейм -
произошла утечка.

Более правильный вариант:
```c++
#include <coroutine>
#include <iostream>

struct task {
    struct promise_type {
        task get_return_object() noexcept {
            return task{std::coroutine_handle<promise_type>::from_promise(*this);
        }

        std::suspend_always initial_suspend() noexcept{
            return std::suspend_always{};
        }

        std::suspend_always final_suspend() noexcept {
            return std::suspend_always{};
        }

        void unhandeled_exception() noexcept {}
    };

    task(std::coroutine_handle<promise_type> handle) : handle(handle) {}

    task(task&& other) noexcept : handle(other.handle) {
        other.handle = nullptr;
    }

    task& operator=(task&& other) {
        if (this == &other)
            return *this;

        if (handle)
            handle.destroy();

        handle = other.handle;
        other.handle = nullptr;
        return *this;
    }

    ~task() {
        handle.destroy();
    }

    std::coroutine_handle<promise_type> handle;
};
```

Ещё прикол:
`co_yield` эквивалентен вот такому коду:
```c++
co_await promise.yield_value(expr);
```
(взято с cppreference)

## Почему именно так
Я не могу нормально объяснить, лучше посмотреть лекцию (28 минута и дальше).
Вроде потому что компилятору так проще делать оптимизации.

## Stackful & stackless
Может показаться, что разница между стекфул и стеклес корутинами большая, но это
не так. Например, есть segmented stack, который аллоцирует дополнительную память
в стеке по мере необходимости - т.е. стекфул корутина с таким стеком будет мало
чем отличаться от стандартной стеклес.

