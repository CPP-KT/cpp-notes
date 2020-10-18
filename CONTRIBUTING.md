 # Contributing

 ### Внесение изменений:

1. Сделать fork репозитория
2. Склонить его к себе
``` 
git clone https://github.com/YOUR_NAME/cpp-notes
```
3. Внести правки, сделать коммит, запушить
```
git commit -m "Your commit message"
git push origin master
```
4. Зайти на github, нажать кнопку new pull request, предложить свои изменения в master основного репозитория

### Добавление изменений основного репозитория в ваш:

1. Сначала нужно добавить основной репозиторий в remote
```
git remote add source https://github.com/lejabque/cpp-notes
git remote -v # должен отобразиться в списке
```
2. Сделать из него ветку
```
git fetch source
git branch -v # должна отобразиться в списке
```
3. Поребейзиться на ветку
```
git rebase source/master
``` 
4. Запушить изменения в свой репозиторий
```
git push origin master # если нужен форспуш, добавьте -f
```