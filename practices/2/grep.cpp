#include <iostream>

using namespace std;

const size_t HAYSTACK_SIZE = 1;

int main(int argc, char *argv[]) {
    if (argc < 3) {
        cout << "Usage: ./grep.out <substring> <filename>\n";
        return EXIT_FAILURE;
    }
    int posInNeedle = 0;
    string needle = argv[1];
    bool flag = false;
    int posInHaystack = 0;

    FILE *file = fopen(argv[2], "r");
    if (!file) {
        perror("File opening failure");
        return EXIT_FAILURE;
    }

    for (;;) {
        char haystack[HAYSTACK_SIZE];
        size_t bytes_read = fread(haystack, sizeof(char), HAYSTACK_SIZE, file);
        if (bytes_read == 0) {
            if (ferror(file)) {
                perror("File reading failure");
                fclose(file);
                return EXIT_FAILURE;
            }
            break;
        }

        for (size_t i = 0; i < bytes_read; i++) {
            if (!flag) {
                if (haystack[i] == needle[0]) {
                    // Сейчас не ищем, позиция может быть началом строки, начинаем сравнивать
                    flag = true;
                    posInNeedle = 1;
                } else {
                    // Сейчас не ищем, позиция не может быть началом строки, пытаемся дальше
                    posInHaystack++;
                }
            } else {
                if (haystack[i] != needle[posInNeedle++]) {
                    // Сейчас ищем, в этой позиции не совпало, надо вернуться назад и снова прочитать
                    flag = false;
                    fseek(file, posInHaystack++, SEEK_SET);
                    break;
                } else {
                    // Сейчас ищем, в этой позиции совпало, может быть даже уже выиграли
                    if (posInNeedle == needle.length()) {
                        cout << "true\n";
                        fclose(file);
                        return 0;
                    }
                }
            }
        }
    }
    fclose(file);
    cout << "false\n";

    return 0;
}
