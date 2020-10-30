#  Анонимные функции, type erasure, std::function
- [Запись лекции №1](https://www.youtube.com/watch?v=ItNnt_7D5w0)
---
## Мотивирующий пример

Какой вариант быстрее?

```c++
bool int_less(int a, int b) {
    return a < b;
}

template <typename T>
struct less {
    bool operator()(T const& a, T const& b) const {
        return a < b;
    }
};

int foo (vector& v) {
    std::sort(v.begin(), v.end(), std::less<int>());
    std::sort(v.begin(), v.end(), &int_less);
}
```

Оказывается, что первый вариант работает процентов на 30 быстрее.