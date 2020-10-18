 # Contributing

 ### Внесение изменений:

1. Сделать fork репозитория
2. Склонить его к себе
``` bash
git clone https://github.com/YOUR_NAME/cpp-notes
```
3. Внести правки, сделать коммит, запушить
```bash
git commit -m "Your commit message"
git push origin master
```
4. Зайти на github, нажать кнопку new pull request, предложить свои изменения в master основного репозитория

### Добавление изменений основного репозитория в ваш:

1. Сначала нужно добавить основной репозиторий в remote (этот шаг нужно делать один раз)
```bash
git remote add source https://github.com/lejabque/cpp-notes
git remote -v # должен отобразиться в списке
```
2. Получить изменения из основного репозитория
```bash
git fetch source
```
3. Поребейзить ваш мастер на мастер основного репозитория
```bash
git checkout master
git rebase source/master
```
4. Запушить изменения в свой репозиторий
```bash
git push origin master # если нужен форспуш, добавьте -f
```