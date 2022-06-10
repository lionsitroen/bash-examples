#!/bin/bash

# example: ./docker-ctrl.sh {start|restart|stop}-front
# example: ./docker-ctrl.sh {start|refresh|restart|stop}-bunch ./configuration.conf
# example: ./docker-ctrl.sh stop-bunch-all

# Имя контейнера и сетевой режим фронтального web-прокси
FRONTNAME="front-nginx"
FRONTINMODE=

# Принимаем аргументы запроса из входящих переменных
DOIT=${1}
BCFG=${2}

# Задаём значения служебных переменных
FORTH=true

# Проверяем наличие ожидаемых приложений и утилит
[ -x "$(command -v docker)" ] && [ -x "$(command -v sudo)" ] && [ -x "$(command -v jq)" ] && [ -x "$(command -v bindfs)" ] && [ -x "$(command -v setfacl)" ] && [ -x "$(command -v pigz)" ] && [ -x "$(command -v git)" ] && [ -x "$(command -v members)" ] && [ -x "$(command -v tee)" ] && [ -x "$(command -v dig)" ] || { echo "Не обнаружен необходимый для работы набор приложений и утилит."; exit 1; }

# Проверяем наличие необходимых входящих переменных
[ ! -z "${DOIT}" ] || { echo "Usage: $(basename $0) {start-front|restart-front|stop-front|start-bunch|refresh-bunch|restart-bunch|stop-bunch|stop-bunch-all|status}"; exit 1; }
if [[ "${DOIT}" = "start-bunch" || "${DOIT}" = "refresh-bunch" || "${DOIT}" = "restart-bunch" || "${DOIT}" = "stop-bunch" ]] && [[ -z "${BCFG}" ]] ; then echo "Usage: $(basename $0) start-bunch|stop-bunch} ./configuration.conf"; exit 1; fi

# Создаём псевдоним для строки даты и включаем передачу его внутрь source-включений
alias cdate='date +"%Y-%m-%d.%H:%M:%S"'
shopt -s expand_aliases

# Указываем Bash-интерпретатору не игнорировать скрытые ".*" файлы
shopt -s dotglob

# Отключаем режим использования как модификатора символа восклицательного знака в текстовых строках
set +o histexpand

# Множеству Docker-контейнеров может не хватить лимита "Kernel Asynchronous I/O" (default: 65536) - будем наращивать его по необходимости
[[ "$(( $(cat /proc/sys/fs/aio-nr) * 2 ))" -gt "$(cat /proc/sys/fs/aio-max-nr)" ]] && echo "$(( $(cat /proc/sys/fs/aio-nr) * 2 + 4096 ))" > /proc/sys/fs/aio-max-nr

# Подключаем (опционально) конфигурационный файл фронтального web-прокси
#source /usr/local/etc/devops/conf/front.conf 2>/dev/null

# Подключаем конфигурационный файл тестового стенда
if [[ "${DOIT}" = "start-bunch" || "${DOIT}" = "refresh-bunch" || "${DOIT}" = "restart-bunch" || "${DOIT}" = "stop-bunch" ]] ; then
  [ -f "${BCFG}" ] && source "${BCFG}"
  [ "${?}" -ne "0" -o -z "${SITENAME}" -o -z "${SITEROOT}" ] && { echo "$(cdate): Конфигурационный файл \"${BCFG}\" отсутствует или его содержимое неприменимо."; exit 1; }
  [[ "${SITEROOT}" != *"/var/www"* ]] && { echo "$(cdate): Данные web-проекта могут быть расположены только в иерархии \"/var/www\" (переменная \"${SITEROOT}\")."; exit 1; }
fi

# Задаём параметры опорных точек файловой иерархии площадки тестирования
[ -z "${OPSROOT}" ] && { OPSROOT="/var/opt/devops"; }
[ ! -d "${OPSROOT}" ] && { mkdir -p "${OPSROOT}"; }
[ ! -d "${OPSROOT}/bunch" ] && { mkdir -p "${OPSROOT}/bunch"; }
[ ! -d "${OPSROOT}/chroot" ] && { mkdir -p "${OPSROOT}/chroot"; }
[ ! -d "${OPSROOT}/share" ] && { mkdir -p "${OPSROOT}/share"; }
setfacl --mask --modify group::rwX,other:--X ${OPSROOT}/bunch
setfacl --mask --set default:group::rwX,default:other:--X ${OPSROOT}/bunch
setfacl --mask --modify group::rwX,other:--X ${OPSROOT}/share
setfacl --mask --set default:group::rwX,default:other:--X ${OPSROOT}/share

# Задаём месторасположение файла публичного журнала событий процедур запуска и остановки контейнеров
if [[ "${DOIT}" = "start-front" || "${DOIT}" = "restart-front" || "${DOIT}" = "stop-front" ]] ; then
  LOG=/var/opt/devops/front/var/www/log/${FRONTNAME}.log
elif [[ "${DOIT}" = "start-bunch" || "${DOIT}" = "refresh-bunch" || "${DOIT}" = "restart-bunch" || "${DOIT}" = "stop-bunch" ]] ; then
  LOG=/var/opt/devops/front/var/www/log/${SITENAME}.log
else
  LOG=/var/opt/devops/front/var/www/log/default.log
fi

# Подключаем библиотеки функций
source /usr/local/etc/devops/lib/front.sh.snippet 2>/dev/null
source /usr/local/etc/devops/lib/bunch.sh.snippet 2>/dev/null
source /usr/local/etc/devops/lib/misc.sh.snippet 2>/dev/null

# Проверяем наличие определяющих способ приёма трафика переменных конфигурации фронтального web-прокси
[ ! -z "${WARPINT}" ] && [ ! -z "${EXTERNIP}" ] && { FRONTINMODE="dedicated"; source /usr/local/etc/devops/lib/front-ip-dedicated.sh.snippet 2>/dev/null; } || { FRONTINMODE="through"; }

# Нормализуем переменные флагов активации подсистем тестового стенда
[ "${SFTP_ENABLE}" != "yes" -a "${SFTP_ENABLE}" != "true" ] && { unset SFTP_ENABLE 2>/dev/null; }
[ "${SCP_ENABLE}" != "yes" -a "${SCP_ENABLE}" != "true" ] && { unset SCP_ENABLE 2>/dev/null; }
[ "${GIT_ENABLE}" != "yes" -a "${GIT_ENABLE}" != "true" ] && { unset GIT_ENABLE 2>/dev/null; }
[ "${MYSQL_ENABLE}" != "yes" -a "${MYSQL_ENABLE}" != "true" ] && { unset MYSQL_ENABLE 2>/dev/null; }
[ "${PMA_ENABLE}" != "yes" -a "${PMA_ENABLE}" != "true" ] && { unset PMA_ENABLE 2>/dev/null; }
[ "${MONGODB_ENABLE}" != "yes" -a "${MONGODB_ENABLE}" != "true" ] && { unset MONGODB_ENABLE 2>/dev/null; }
[ "${MEMCACHED_ENABLE}" != "yes" -a "${MEMCACHED_ENABLE}" != "true" ] && { unset MEMCACHED_ENABLE 2>/dev/null; }
[ "${PHPFPM_ENABLE}" != "yes" -a "${PHPFPM_ENABLE}" != "true" ] && { unset PHPFPM_ENABLE 2>/dev/null; }
[ "${NODEJS_ENABLE}" != "yes" -a "${NODEJS_ENABLE}" != "true" ] && { unset NODEJS_ENABLE 2>/dev/null; }
[ "${HOOK_ENABLE}" != "yes" -a "${HOOK_ENABLE}" != "true" ] && { unset HOOK_ENABLE 2>/dev/null; }

# Описываем функцию процедур запуска фронтального web-прокси
function start-front {

  # Предварительно проверяем наличие необходимых виртуальных сетей и активируем их в случае отсутствия
  [ "${FRONTINMODE}" = "dedicated" ] && [ "$(docker network ls | grep -c -i frontnet)" -eq "0" ] && { docker network create --driver bridge frontnet > /dev/null; }
  [ "$(docker network ls | grep -c -i vianet)" -eq "0" ] && { docker network create --driver bridge vianet > /dev/null; }

  # Проверяем, не запущен ли уже фронтальный web-прокси
  if [ `docker ps | grep -c -i "${FRONTNAME}"` -eq 0 ] ; then

    # Подготавливаем конфигурацию контейнера фронтального web-прокси
    front-preset

    # Пробуем запустить фронтальный web-прокси
    front-nginx-start

    # Открываем пользователям группы "developer" доступ к web-интерфейсу просмотра журналов событий
    front-web-view-enable

  else
    echo "$(cdate): Запуск не требуется: контейнер \"${FRONTNAME}\" уже работает."
  fi

  # Пробуем активировать пересылку трафика к фронтальному web-прокси (при необходимости)
  [ "${FRONTINMODE}" = "dedicated" ] && { front-ip-start; }

return ${?}
}

# Описываем функцию процедур перезапуска фронтального web-прокси без обновления конфигурации и файлов данных
function restart-front {

  # Проверяем, запущен ли фронтальный web-прокси
  if [ `docker ps | grep -c -i "${FRONTNAME}"` -ge 1 ] ; then
    echo "$(cdate): Запущена процедура перезапуска фронтального web-прокси без замены конфигурации." | tee -a "${LOG}"

    # Останавливаем фронтальный web-прокси
    front-nginx-stop

    # Ожидаем остановки контейнера в течении десяти секунд
    echo -n "$(cdate): Ожидаем остановки контейнера фронтального web-прокси... " | tee -a "${LOG}"
    for try in {1..10} ; do
      [ `docker ps | grep -c -i "${FRONTNAME}"` -eq 0 ] && {
        break
      } || { echo -n "#"; sleep 1; }
    done ; echo | tee -a "${LOG}"

    # Запускаем фронтальный web-прокси
    front-nginx-start

    # Открываем пользователям группы "developer" доступ к web-интерфейсу просмотра журналов событий
    front-web-view-enable

  else
    echo "$(cdate): Перезапуск фронтального web-прокси невозможен: он не работает в данный момент."
  fi

return ${?}
}

# Описываем функцию процедур остановки фронтального web-прокси
function stop-front {

  # Проверяем, не запущены ли зависимые контейнеры
  if [ "$(docker ps | grep -c -i bunch-)" -eq "0" ] ; then

    # Пробуем остановить пересылку трафика к фронтальному web-прокси
    [ "${FRONTINMODE}" = "dedicated" ] && { front-ip-stop; }

    # Пробуем остановить фронтальный web-прокси
    front-nginx-stop

    # Удаляем всю иерархию файлов, созданных для контейнера фронтального web-прокси
    rm -rf /var/opt/devops/front

    # Удаляем все неиспользуемые в данный момент контейнеры и виртуальные сети
    docker system prune --force > /dev/null
    docker network prune --force > /dev/null

  else
    FORTH=false;
    echo "$(cdate): Нельзя останавливать фронтальный web-прокси, когда ещё запущены зависимые от него контейнеры."
  fi

return ${?}
}

# Описываем функцию процедур запуска группы контейнеров тестового стенда
function start-bunch {

  # Профилактически пробуем запустить фронтальный web-прокси
  # (все сервисы зависят от или взаимодействуют с фронтальным web-прокси)
  start-front
  if [ "${FORTH}" = "true" ] ; then

    # Проверяем, запущены ли какие-нибудь контейнеры тестового стенда
    if [ `docker ps | grep -c -i -e "bunch-${SITENAME}-"` -eq 0 ] ; then

      # Предварительно проверяем наличие необходимой виртуальной сети и активируем её в случае отсутствия
      [ "$(docker network ls | grep -c -i backnet-${SITENAME})" -eq "0" ] && { docker network create --driver bridge backnet-${SITENAME} > /dev/null; }

      # Подготовка конфигурационных файлов контейнеров
      bunch-preset

      # Пробуем обеспечить доступ к файловой системе тестируемого web-проекта
      [ ${SFTP_ENABLE} ] && bunch-sftp-enable

      # Пробуем загрузить данные тестируемого web-проекта
      [ ${SCP_ENABLE} ] && bunch-scp-download
      [[ ${SCP_ENABLE} && ${#SCP_EXT_DIR_SRC[@]} -gt 0 ]] && bunch-scp-ext-sync
      [ ${GIT_ENABLE} ] && bunch-git-download

      # Пробуем запустить контейнеры тестового стенда
      [ ${MYSQL_ENABLE} ] && bunch-mysql-start
      [ ${MONGODB_ENABLE} ] && bunch-mongodb-start
      [ ${MEMCACHED_ENABLE} ] && bunch-memcached-start
      [ ${PHPFPM_ENABLE} ] && bunch-php-start
      [ ${NODEJS_ENABLE} ] && bunch-nodejs-start

      # Пробуем запустить загрузку данных из исходной БД PostgreSQL
      [ ${POSTGRESQL_ENABLE} ] && bunch-postgresql-download

      # Пробуем запустить загрузку данных из исходной БД MySQL
      [ ${MYSQL_ENABLE} ] && bunch-mysql-download

      # Пробуем запустить загрузку данных из исходной БД MongoDB
      [ ${MONGODB_ENABLE} ] && bunch-mongodb-download

      # Пробуем запустить контейнеры впомогательных инструментов администрирования
      [ ${PMA_ENABLE} ] && bunch-pma-start

      # Пробуем выполнить корректирующие Shell-команды
      [ ${HOOK_ENABLE} ] && bunch-hook-exec

      # Пробуем запустить принимающий запросы контейнер web-сервиса
      bunch-nginx-start

    else

      # Останавливаем принимающий запросы контейнер web-сервиса
      bunch-nginx-stop

      # Запускаем процедуры синхронизации данных
      refresh-bunch

      # Запускаем процедуры профилактического перезапуска контейнеров без замены конфигурации
      restart-bunch

    fi
  else
    FORTH=false;
    echo "$(cdate): Запуск тестового стенда без фронтального web-прокси невозможен."
  fi

return ${?}
}

# Описываем функцию процедур обновления данных группы контейнеров тестового стенда без перезапуска таковых
function refresh-bunch {

  # Проверяем, запущены ли какие-нибудь контейнеры тестового стенда
  if [ `docker ps | grep -c -i -e "bunch-${SITENAME}-"` -ge 1 ] ; then
    echo "$(cdate): Запущена процедура обновления данных тестового стенда." | tee -a "${LOG}"

    # Останавливаем web-прокси тестового стенда
    bunch-nginx-stop

    # Отключаем доступ к файловой системе тестируемого web-проекта
    [ ${SFTP_ENABLE} ] && bunch-sftp-disable

    # Останавливаем NodeJS-сервис
    [ ${NODEJS_ENABLE} ] && bunch-nodejs-stop

    # Пробуем обновить и загрузить данные тестируемого web-проекта
    [ ${SCP_ENABLE} ] && bunch-scp-sync
    [[ ${SCP_ENABLE} && ${#SCP_EXT_DIR_SRC[@]} -gt 0 ]] && bunch-scp-ext-sync
    [ ${GIT_ENABLE} ] && bunch-git-download

    # Пробуем запустить загрузку данных из исходной БД MySQL
    [ ${MYSQL_ENABLE} ] && bunch-mysql-download

    # Пробуем запустить загрузку данных из исходной БД MongoDB
    [ ${MONGODB_ENABLE} ] && bunch-mongodb-download

    # Запускаем NodeJS-сервис
    [ ${NODEJS_ENABLE} ] && bunch-nodejs-start

    # Пробуем выполнить корректирующие Shell-команды
    [ ${HOOK_ENABLE} ] && bunch-hook-exec

    # Пробуем обеспечить доступ к файловой системе тестируемого web-проекта
    [ ${SFTP_ENABLE} ] && bunch-sftp-enable

    # Запускаем web-прокси тестового стенда
    bunch-nginx-start

  else
    echo "$(cdate): Обновление данных тестовой схемы невозможно: она не работает в данный момент."
  fi

return ${?}
}

# Описываем функцию процедур перезапуска группы контейнеров тестового стенда без обновления конфигурации и данных
function restart-bunch {

  # Проверяем, запущены ли какие-нибудь контейнеры тестового стенда
  if [ `docker ps | grep -c -i -e "bunch-${SITENAME}-"` -ge 1 ] ; then
    echo "$(cdate): Запущена процедура перезапуска контейнеров тестового стенда без обновления конфигурации и данных." | tee -a "${LOG}"

    # Отключаем доступ к файловой системе тестируемого web-проекта
    [ ${SFTP_ENABLE} ] && bunch-sftp-disable

    # Останавливаем контейнеры тестового стенда
    bunch-nginx-stop
    [ ${PMA_ENABLE} ] && bunch-pma-stop
    [ ${NODEJS_ENABLE} ] && bunch-nodejs-stop
    [ ${PHPFPM_ENABLE} ] && bunch-php-stop
    [ ${MEMCACHED_ENABLE} ] && bunch-memcached-stop
    [ ${MONGODB_ENABLE} ] && bunch-mongodb-stop
    [ ${MYSQL_ENABLE} ] && bunch-mysql-stop

    # Ожидаем остановки всех контейнеров в течении одной минуты
    echo -n "$(cdate): Ожидаем остановки контейнеров тестового стенда... " | tee -a "${LOG}"
    for try in {1..60} ; do
      [ `docker ps | grep -c -i -e "bunch-${SITENAME}-"` -eq 0 ] && {
        break
      } || { echo -n "#"; sleep 1; }
    done ; echo | tee -a "${LOG}"

    # Пробуем обеспечить доступ к файловой системе тестируемого web-проекта
    [ ${SFTP_ENABLE} ] && bunch-sftp-enable

    # Пробуем запустить контейнеры тестового стенда
    [ ${MYSQL_ENABLE} ] && bunch-mysql-start
    [ ${MONGODB_ENABLE} ] && bunch-mongodb-start
    [ ${MEMCACHED_ENABLE} ] && bunch-memcached-start
    [ ${PHPFPM_ENABLE} ] && bunch-php-start
    [ ${NODEJS_ENABLE} ] && bunch-nodejs-start
    [ ${PMA_ENABLE} ] && bunch-pma-start
    bunch-nginx-start

  else
    echo "$(cdate): Перезапуск контейнеров тестовой схемы невозможен: нет работающих в данный момент."
  fi

return ${?}
}

# Описываем функцию процедур остановки группы контейнеров тестового стенда
function stop-bunch {

  # Останавливаем контейнеры тестового стенда
  bunch-nginx-stop
  [ ${PMA_ENABLE} ] && bunch-pma-stop
  [ ${NODEJS_ENABLE} ] && bunch-nodejs-stop
  [ ${PHPFPM_ENABLE} ] && bunch-php-stop
  [ ${MEMCACHED_ENABLE} ] && bunch-memcached-stop
  [ ${MONGODB_ENABLE} ] && bunch-mongodb-stop
  [ ${MYSQL_ENABLE} ] && bunch-mysql-stop

  # Удаляем возможно имеющиеся crontab-записи для этого контейнера
  crontab -u root -l | sed -E "s/.*docker\s*exec.*bunch-${SITENAME}.*//gI" | crontab -u root -

  # Отключаем доступ к файловой системе тестируемого web-проекта
  [ ${SFTP_ENABLE} ] && bunch-sftp-disable

  # Удаляем выделенную только для тестового стенда виртуальную сеть
  docker network rm backnet-${SITENAME} > /dev/null 2>&1

  # Перебираем все смонтированные в тестовый стенд ресурсы и демонтируем их
  BINDED=( $(mount | awk '{print $3}' | grep -i "${OPSROOT}/bunch/${SITENAME}") )
  for BINDED_ITEM in ${BINDED[@]} ; do
    umount "${BINDED_ITEM}" > /dev/null 2>&1
  done

  # После завершения работы контейнеров тестового стенда удаляем всю иерархию их файлов
  echo "$(cdate): Запущена процедура удаления данных выключаемого тестового стенда." | tee -a "${LOG}"
  rm -rf ${OPSROOT}/bunch/${SITENAME}

  # Удаляем настройки проксирования и указываем web-серверу фронтального контейнера принять обновлённую (очищенную) конфигурацию
  for FQDN_ITEM in "${FQDN[@]}" ; do
    rm -f /var/opt/devops/front/etc/nginx/bunch.d/${FQDN_ITEM}.conf
  done
  docker exec -i ${FRONTNAME} /bin/bash -c "nginx -s reload" > /dev/null 2>&1

return ${?}
}

# Описываем функцию процедур остановки всех тестовых стендов
function stop-bunch-all {

  # Останавливаем все контейнеры, кроме фронтального web-прокси
  if [ "$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i -v -e 'front-')" ] ; then

    # Перебираем все контейнеры тестовых стендов, поименно
    CONTAINERS=( $(docker ps --format '{{.Names}}' 2>/dev/null | grep -i -v -e "^front-") )
    for CONTAINER in ${CONTAINERS[@]} ; do

      # Задаём месторасположение файла журнала для каждого тестового стенда индивидуально
      LOG="/var/opt/devops/front/var/www/log/$(echo ${CONTAINER} | sed 's/^bunch-//' | sed 's/-[^-]*$//').log"

      # Останавливаем контейнер
      docker stop ${CONTAINER} > /dev/null 2>&1
      if [ "${?}" -eq "0" ] ; then
        echo "$(cdate): Контейнер \"${CONTAINER}\" успешно остановлен." | tee -a "${LOG}"
      else
        FORTH=false
        echo "$(cdate): Сбой при остановке контейнера \"${CONTAINER}\"." | tee -a "${LOG}"
      fi
    done

    # Приводим окружение к исходному виду
    unset CONTAINERS; unset CONTAINER
    LOG=/var/opt/devops/front/var/www/log/default.log
  fi

  # Удаляем возможно имеющиеся crontab-записи контейнеров тестовых стендов
  crontab -u root -l | sed -E "s/.*docker\s*exec.*bunch-.*//gI" | crontab -u root -

  # Удаляем выделенные только для тестовых стендов виртуальные сети
  docker network rm $(docker network ls --format '{{.Name}}\t{{.ID}}' | grep -i -e "^backnet-" | awk '{print $2}') > /dev/null 2>&1

  # После завершения работы контейнеров тестовых стендов удаляем конфигурационные и файлы данных
  rm -rf ${OPSROOT}/bunch/*

  # Перебираем все смонтированные в пользовательские "chroot"-ы ресурсы и демонтируем их
  CHROOTED=( $(df --output=target | grep -i "/var/opt/devops/chroot/") )
  for CHROOTED_ITEM in ${CHROOTED[@]} ; do
    umount "${CHROOTED_ITEM}" > /dev/null 2>&1
  done

  # Перебираем все смонтированные в тестовые стенды ресурсы и демонтируем их
  BINDED=( $(mount | awk '{print $3}' | grep -i "${OPSROOT}/bunch") )
  for BINDED_ITEM in ${BINDED[@]} ; do
    umount "${BINDED_ITEM}" > /dev/null 2>&1
  done

  # Удаляем настройки проксирования и указываем web-серверу фронтального контейнера принять обновлённую (очищенную) конфигурацию
  rm -f /var/opt/devops/front/etc/nginx/bunch.d/*.conf
  docker exec -i ${FRONTNAME} /bin/bash -c "nginx -s reload" > /dev/null 2>&1

return ${?}
}

# Описываем функцию проверки успешности запуска всех контейнеров тестового стенда
function status-bunch {

  # Получаем перечень запущенных в данный момент контейнеров тестового стенда
  CONTAINERS=( $(docker ps --format '{{.Names}}' 2>/dev/null | grep -i -v -e "^front-" | grep -i "bunch-${SITENAME}-") )

  # Сверяемся со списком контейнеров, которые должны быть запущены  
  [[ ${MYSQL_ENABLE} && " ${CONTAINERS[*]} " != *" bunch-${SITENAME}-mysql "* ]] && { FORTH=false; echo "$(cdate): Контейнер \"bunch-${SITENAME}-mysql\" не запущен." | tee -a "${LOG}"; }
  [[ ${MONGODB_ENABLE} && " ${CONTAINERS[*]} " != *" bunch-${SITENAME}-mongodb "* ]] && { FORTH=false; echo "$(cdate): Контейнер \"bunch-${SITENAME}-mongodb\" не запущен." | tee -a "${LOG}"; }
  [[ ${MEMCACHED_ENABLE} && " ${CONTAINERS[*]} " != *" bunch-${SITENAME}-memcached "* ]] && { FORTH=false; echo "$(cdate): Контейнер \"bunch-${SITENAME}-memcached\" не запущен." | tee -a "${LOG}"; }
  [[ ${PHPFPM_ENABLE} && " ${CONTAINERS[*]} " != *" bunch-${SITENAME}-php "* ]] && { FORTH=false; echo "$(cdate): Контейнер \"bunch-${SITENAME}-php\" не запущен." | tee -a "${LOG}"; }
  [[ ${NODEJS_ENABLE} && " ${CONTAINERS[*]} " != *" bunch-${SITENAME}-nodejs "* ]] && { FORTH=false; echo "$(cdate): Контейнер \"bunch-${SITENAME}-nodejs\" не запущен." | tee -a "${LOG}"; }
  [[ ${PMA_ENABLE} && " ${CONTAINERS[*]} " != *" bunch-${SITENAME}-pma "* ]] && { FORTH=false; echo "$(cdate): Контейнер \"bunch-${SITENAME}-pma\" не запущен." | tee -a "${LOG}"; }
  [[ " ${CONTAINERS[*]} " != *" bunch-${SITENAME}-nginx "* ]] && { FORTH=false; echo "$(cdate): Контейнер \"bunch-${SITENAME}-nginx\" не запущен." | tee -a "${LOG}"; }

return ${?}
}

# Описываем функцию вывода текущего статуса компонентов схемы
function status {
  echo
  echo "Info: Available Interfaces & IP:"
  ip -o addr show scope global | awk '{split($4, a, "/"); print $2" : "a[1]}'
  echo
  echo "Info: Currently Active Containers:"
  docker ps --format 'table {{.ID}}\t{{.Image}}\t{{.Names}}'
  front-nginx-log-show
return ${?}
}

# Отрабатываем процедуры запуска и остановки контейнеров
case "${DOIT}" in
"start-front")

  # Пробуем запустить фронтальный web-прокси
  start-front
  front-nginx-log-show

  # Если при запуске фронтального web-прокси случился сбой, то разбираем схему
  if [ "${FORTH}" != "true" ] ; then
    stop-front
  fi

;;
"stop-front")

  # Пробуем остановить фронтальный web-прокси
  stop-front
  front-nginx-log-show

;;
"restart-front")

  # Пробуем перезапустить (без обновления конфигурации) фронтальный web-прокси
  restart-front
  front-nginx-log-show

;;
"start-bunch")

  # Пробуем запустить группу контейнеров тестового стенда
  start-bunch
  front-nginx-log-show

  # Проверяем успешность запуска контейнеров тестового стенда
  status-bunch

  # Разбираем схему при любом сбое на этапе запуска контейнеров тестового стенда
  if [ "${FORTH}" != "true" ] ; then
    stop-bunch
  fi

;;
"refresh-bunch")

  # Пробуем обновить файлы данных группы контейнеров тестового стенда (без перезапуска таковых)
  refresh-bunch
  front-nginx-log-show

;;
"restart-bunch")

  # Пробуем перезапустить (без обновления конфигурации и данных) группу контейнеров тестового стенда
  restart-bunch
  front-nginx-log-show

  # Проверяем успешность запуска контейнеров тестового стенда
  status-bunch

;;
"stop-bunch")

  # Пробуем остановить группу контейнеров тестового стенда
  stop-bunch
  front-nginx-log-show

;;
"stop-bunch-all")

  # Пробуем остановить все группы контейнеров тестовых стендов
  stop-bunch-all
  front-nginx-log-show

;;
"status") status; ;;
*) echo "$(cdate): Некорректно указан тип операции \"${DOIT}\"."; FORTH=false; ;;
esac

# При любом сбое постфактум информируем о текущем состоянии
if [ "${FORTH}" != "true" ] ; then
  status
fi

# Профилактически чистим директорию журналов от устаревших файлов
front-nginx-log-cleaning

exit ${?}
