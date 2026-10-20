# Новые тексты: обычный режим и быстрый расширенный словарь

Синтетические RU→EN примеры. Показан последний успешный измеренный повтор; ошибки перечислены явно. Это материалы для ручной оценки, а не автоматическая оценка качества.

## Контур охлаждения — без кавычек

### Исходник

Испытание охлаждения

На испытательном стенде проверили замкнутый контур охлаждения лазерного станка. Насос подавал воду через фильтр и теплообменник, после чего она возвращалась в резервуар. При расходе 18 литров в минуту температура на выходе держалась на уровне 27 градусов. Это результат лабораторного испытания, а не обещание такой же температуры при любой нагрузке. Оператор записывал показания каждые пять минут и не менял настройки во время серии.

После замены фильтра давление перед теплообменником снизилось, однако расход остался прежним. Инженер Анна предположила, что часть воды проходит через обходной клапан. Она попросила техника закрыть его только на время измерения. Техник выполнил просьбу, но затем вернул клапан в исходное положение: оставлять его закрытым при остановке насоса запрещено. Никаких признаков утечки в соединениях не обнаружили.

Вторая серия длилась 45 минут. Датчик на обратной линии сначала показал скачок температуры, хотя два контрольных термометра его не подтвердили. Не следует считать этот скачок доказательством перегрева. После проверки кабеля показания датчика совпали с контрольными. Анна предложила заменить разъём, а сам датчик пока сохранить; руководитель согласился именно с этим порядком работ.

В отчёте необходимо различать расход воды и расход электроэнергии. Насос потреблял 240 ватт, но из этого числа нельзя вычислить объём воды без дополнительных данных. Следующее испытание назначено на 14 июня, резервное — на 17 июня. Если новый разъём не доставят вовремя, заменят дату испытания, а не насос. Заказчику отправят только проверенные результаты обеих серий.

### Критерии, зафиксированные до измерений

- 18 L/min and 27 degrees are laboratory observations, not universal promises
- Valve must not remain closed when pump stops; temporary closure reversed
- Temperature spike not confirmed, no proven overheating
- Replace connector, retain sensor; 240 W is not water flow
- June 14 primary / June 17 reserve; delay test rather than replace pump

### Обычный режим

Первая содержательная часть 2.99 с; весь текст 9.53 с; подготовка 0.00 с (включена).

Cooling Test

A closed-loop cooling system for a laser machine was tested on a test bench. The pump circulated water through a filter and a heat exchanger, after which it returned to the reservoir. At a flow rate of 18 liters per minute, the outlet temperature remained at 27 degrees. This is the result of a laboratory test, not a guarantee of the same temperature under any load. The operator recorded the readings every five minutes and did not change the settings during the test series.

After replacing the filter, the pressure before the heat exchanger decreased, but the flow rate remained the same. Engineer Anna suspected that some of the water was passing through the bypass valve. She asked the technician to close it only temporarily. The technician complied, but then returned the valve to its original position: leaving it closed when the pump is off is prohibited. No signs of leaks were found at the connections.

The second episode lasted 45 minutes. The sensor on the return line initially showed a temperature spike, although two control thermometers did not confirm it. This spike should not be considered evidence of overheating. After checking the cable, the sensor's readings matched those of the control thermometers. Anna suggested replacing the connector while keeping the sensor itself for now; the supervisor agreed with this course of action.

The report must distinguish between water consumption and electricity consumption. The pump consumed 240 watts, but this figure alone cannot be used to calculate the water volume without additional data. The next test is scheduled for June 14, with a backup test on June 17. If the new connector is not delivered on time, the test date will be changed, not the pump. The client will only receive the verified results from both test series.


### Быстрый расширенный словарь

Первая содержательная часть 5.52 с; весь текст 12.69 с; подготовка 2.18 с (включена).

Cooling test

On the test bench, a closed-loop cooling system for a laser machine was tested. The pump supplied water through a filter and a heat exchanger, after which it returned to the reservoir. At a flow rate of 18 liters per minute, the outlet temperature remained at 27 degrees. This is the result of a laboratory test, not a guarantee of the same temperature under any load. The operator recorded the readings every five minutes and did not change the settings during the series.

After replacing the filter, the pressure before the heat exchanger decreased, but the flow rate remained the same. Engineer Anna suspected that some of the water was passing through the bypass valve. She asked the technician to close it only temporarily. The technician complied, but then returned the valve to its original position: leaving it closed when the pump is turned off is prohibited. No signs of leakage were found at the connections.

The second series lasted 45 minutes. The sensor on the return line initially showed a temperature spike, although two control thermometers did not confirm it. This spike should not be considered evidence of overheating. After checking the cable, the sensor's readings matched those of the control thermometers. Anna suggested replacing the connector while keeping the sensor for now; the supervisor agreed to this sequence of actions.

The report must distinguish between water flow rate and electrical power consumption. The pump consumed 240 watts, but this figure alone cannot be used to calculate the water volume without additional data. The next test is scheduled for June 14, with a backup test on June 17. If the new connector is not delivered on time, the test date will be changed, not the pump. The client will only receive the verified results from both test series.

Термины:

- Насос → Pump
- воду → water
- расходе → flow rate
- Испытание → test
- охлаждения → cooling
- фильтр → filter
- теплообменник → heat exchanger
- минуту → minute
- температура → temperature
- результат → result
## Очередь запросов и кеш — без кавычек

### Исходник

Обновление сервиса

Сервис принимает запросы на построение отчётов и помещает их в очередь. Короткие запросы обрабатываются сразу, а большие отчёты выполняются фоновым процессом. Кеш хранит готовый результат только десять минут. Если пользователь повторно отправляет тот же запрос в этот срок, сервер возвращает сохранённый ответ. Это не означает, что новый запрос исчезает: в журнале остаётся отдельная запись с указанием источника результата.

После обновления обнаружили ошибку: отменённый запрос иногда оставался в очереди и запускался позже. Программист Олег сначала предложил очищать всю очередь при отмене, но коллега объяснила, что тогда будут потеряны чужие задания. Решили удалять только запись с совпадающим идентификатором. Отмена одного отчёта не должна менять состояние остальных отчётов и не должна очищать их кеш.

В проверочной серии отправили 120 запросов, отменили 17 и получили 103 результата. Повторный запуск использовал новый кеш, поэтому времена первого и второго запусков нельзя складывать и называть временем одного отчёта. Самый большой отчёт строился 8,4 секунды, а первый фрагмент появился через 1,2 секунды. Фрагмент ещё не является завершённым результатом и не должен попадать в постоянную историю как готовый отчёт.

При сбое сети клиент сохраняет номер задания и повторяет проверку его состояния. Он не должен создавать новое задание при каждой попытке соединения. Если сервер уже закончил работу, клиент скачивает готовый файл. Если задание было отменено, клиент показывает отмену и предлагает запустить его заново вручную. Автоматически возобновлять отменённый запрос нельзя, даже если в кеше осталась похожая версия отчёта.

### Критерии, зафиксированные до измерений

- Cache lasts ten minutes; repeated request still logged separately
- Only matching job is cancelled, not entire queue or others' cache
- 120 requests minus 17 cancelled equals 103 results
- 8.4 s total versus 1.2 s first fragment; partial is not final history
- Network retry checks same job; cancelled job never auto-resumes

### Обычный режим

Первая содержательная часть 2.76 с; весь текст 10.42 с; подготовка 0.00 с (включена).

Service Update

The service accepts report generation requests and places them in a queue. Short requests are processed immediately, while larger reports are handled by a background process. The cache stores the generated result for only ten minutes. If a user resubmits the same request within this timeframe, the server returns the cached response. This does not mean that the new request is discarded: a separate entry remains in the log, indicating the source of the result.

After the update, a bug was discovered: canceled requests sometimes remained in the queue and were executed later. Programmer Oleg initially suggested clearing the entire queue upon cancellation, but a colleague explained that this would result in losing other people's tasks. They decided to delete only the entry with the matching identifier. Canceling one report should not alter the state of other reports or clear their cache.

In the test series, 120 requests were sent, 17 were canceled, and 103 results were obtained. The rerun used a new cache, so the times from the first and second runs cannot be combined and referred to as the time for a single report. The largest report took 8.4 seconds to generate, while the first fragment appeared after 1.2 seconds. A fragment is not yet a complete result and should not be added to the permanent history as a finished report.

In the event of a network failure, the client saves the task ID and retries checking its status. It should not create a new task with each connection attempt. If the server has already shut down, the client downloads the completed file. If the task was canceled, the client displays a cancellation message and offers to restart it manually. A canceled request must not be automatically resumed, even if a similar version of the report remains in the cache.


### Быстрый расширенный словарь

Первая содержательная часть 4.78 с; весь текст 12.32 с; подготовка 2.06 с (включена).

Service Update

The service accepts requests to generate reports and places them in a queue. Short requests are processed immediately, while large reports are handled by a background process. The cache stores the result for only ten minutes. If a user resends the same request within this period, the server returns the saved response. This does not mean that the new request disappears: a separate entry remains in the log, indicating the source of the result.

After the Update, we discovered a bug: a cancelled request sometimes remained in the queue and was executed later. Programmer Oleg initially suggested clearing the entire queue upon cancellation, but a colleague explained that this would result in the loss of others' tasks. We decided to delete only the entry with the matching identifier. Cancelling one report should not alter the state of other reports or clear their cache.

In the test series, 120 requests were sent, 17 were canceled, and 103 results were obtained. The rerun used a new cache, so the times from the first and second runs cannot be added together and referred to as the time of a single report. The largest report took 8.4 seconds to generate, while the first fragment appeared after 1.2 seconds. A fragment is not yet a completed result and should not be added to the permanent history as a finished report.

In the event of a network failure, the client saves the task number and repeats the check of its status. It should not create a new task with every connection attempt. If the server has already shut down, the client downloads the completed file. If the task was canceled, the client displays the cancellation and offers to restart it manually. An canceled request cannot be automatically resumed, even if a similar version of the report remains in the cache.

Термины:

- отчётов → reports
- запросы → requests
- результат → result
- задания → tasks
- Обновление → Update
- сервиса → service
- очередь → queue
- сервер → server
- запись → entry
- отмене → cancellation
## Перенос поставки — без кавычек

### Исходник

План доставки

Поставщик подготовил три партии деталей для сборочного цеха. Первая партия состоит из 480 корпусов, вторая — из 960 крышек, а третья содержит запасные уплотнения. Наличие деталей на складе ещё не означает, что груз передан перевозчику. Отгрузку подтверждает подписанная накладная; автоматическое уведомление о создании заказа таким подтверждением не считается.

Диспетчер сообщил, что машина прибудет во вторник между девятью и одиннадцатью часами. Однако кладовщик сможет принять груз только после десяти. Поэтому водитель должен сначала доставить крышки на соседний склад, а затем привезти корпуса в цех. Переставлять адреса в накладных не требуется: меняется порядок остановок, а не получатели. Если первая остановка затянется, водитель обязан позвонить диспетчеру.

При приёмке обнаружили повреждение двух коробок. Это не означает повреждения всех деталей внутри: коробки отделили от остальных и вскрыли в присутствии представителя перевозчика. Из 40 проверенных корпусов три оказались непригодны. Их не нужно включать в число годных, даже если поставщик обещал замену. Остальные 37 можно использовать после повторного осмотра поверхности.

Счёт за перевозку выставят отдельно от счёта за детали. Оплата доставки не подтверждает оплату самих изделий. Финансовый отдел попросил указать номер заказа в обоих документах, но не объединять суммы в одну строку. Замена трёх корпусов должна прибыть до пятницы; если этого не произойдёт, запуск линии перенесут на понедельник. Штраф автоматически не начисляется: решение принимают после проверки условий договора.

### Критерии, зафиксированные до измерений

- 480 housings and 960 lids, signed waybill proves handover
- Tuesday 9–11 arrival versus receiver available after 10; order changes not recipients
- Two damaged boxes do not mean all contents damaged
- 40 inspected / 3 unusable / 37 potentially usable, replacement not counted yet
- Transport and goods invoices/payment separate; Friday replacement or Monday line start; no automatic penalty

### Обычный режим

Первая содержательная часть 2.64 с; весь текст 10.72 с; подготовка 0.00 с (включена).

Delivery Plan

The supplier has prepared three batches of parts for the assembly workshop. The first batch consists of 480 housings, the second of 960 covers, and the third contains spare seals. The availability of parts in the warehouse does not yet mean that the goods have been handed over to the carrier. The shipment is confirmed by a signed delivery note; an automatic order creation notification is not considered such confirmation.

The dispatcher reported that the vehicle will arrive on Tuesday between nine and eleven o'clock. However, the warehouse worker will only be able to accept the cargo after ten. Therefore, the driver must first deliver the lids to the neighboring warehouse and then bring the casings to the workshop. There is no need to change the addresses on the delivery notes: only the order of stops is changing, not the recipients. If the first stop is delayed, the driver must call the dispatcher.

During acceptance, damage to two boxes was discovered. This does not mean that all the parts inside are damaged: the boxes were separated from the rest and opened in the presence of a carrier representative. Out of the 40 inspected units, three were found to be unsuitable. These should not be included in the count of acceptable units, even if the supplier promised a replacement. The remaining 37 can be used after a re-inspection of their surfaces.

The shipping invoice will be issued separately from the parts invoice. Payment for delivery does not confirm payment for the products themselves. The finance department has requested that the order number be included in both documents, but that the amounts not be combined into a single line. The replacement of the three housings must arrive by Friday; if this does not happen, the line’s launch will be postponed to Monday. A penalty is not automatically applied: a decision is made after reviewing the terms of the contract.


### Быстрый расширенный словарь

Первая содержательная часть 5.21 с; весь текст 13.80 с; подготовка 2.16 с (включена).

Delivery Plan

The Supplier has prepared three batches of parts for the assembly workshop. The first batch consists of 480 housing units, the second contains 960 covers, and the third includes spare seals. The availability of parts in the warehouse does not yet mean that the shipment has been handed over to the carrier. Dispatch is confirmed by a signed delivery note; an automatic notification of order creation is not considered such confirmation.

The dispatcher reported that the vehicle will arrive on Tuesday between nine and eleven o'clock. However, the warehouse worker will only be able to accept the shipment after ten. Therefore, the driver must first deliver the covers to the adjacent warehouse and then bring the housing units to the workshop. There is no need to change the addresses on the waybills: only the order of stops is changing, not the recipients. If the first stop is delayed, the driver is required to call the dispatcher.

During acceptance, damage to two boxes was discovered. This does not mean that all the parts inside are damaged: the boxes were separated from the rest and opened in the presence of a carrier representative. Out of the 40 inspected housing units, three were found to be unsuitable. They should not be included in the count of acceptable units, even if the Supplier promised a replacement. The remaining 37 can be used after a re-inspection of their surfaces.

The shipping invoice will be issued separately from the parts invoice. Payment for delivery does not confirm payment for the products themselves. The finance department has requested that the order number be included in both documents, but that the amounts not be combined into a single line. The replacement for the three housing units must arrive by Friday; if this does not happen, the line launch will be postponed to Monday. A penalty is not automatically applied: a decision is made after reviewing the terms of the contract.

Термины:

- деталей → parts
- корпусов → housing units
- Поставщик → Supplier
- доставки → delivery
- партии → batches
- крышек → covers
- складе → warehouse
- груз → shipment
- перевозчику → carrier
- заказа → order
## Горячий резерв — контроль с кавычками

### Исходник

Резервирование сервера

В новой схеме резервирования второй сервер работает в режиме «горячего резерва». Он получает копии записей, но не отвечает на пользовательские запросы, пока основной сервер исправен. Термин «горячий резерв» не связан с температурой оборудования. Он означает, что резервный сервер готов быстро принять нагрузку без полной повторной загрузки данных.

При проверке основной сервер отключили от сети на 90 секунд. Резервный сервер начал отвечать через четыре секунды, а часть клиентов повторила запрос самостоятельно. Два одинаковых запроса не должны создавать две одинаковые покупки. Поэтому каждому заказу присваивается постоянный ключ, который сохраняется при повторной отправке. Ключ используется для распознавания заказа, а не для шифрования его содержимого.

После восстановления связи нельзя сразу считать старый основной сервер главным. Сначала необходимо сравнить номера последних подтверждённых записей и перенести недостающие изменения. Если оба сервера одновременно начнут принимать новые заказы независимо друг от друга, возникнет расхождение данных. В инструкции такой случай назван «разделением кластера»; при «разделении кластера» запись должна быть разрешена только одной стороне.

Для отдельного архива выбран холодный резерв: его включают вручную, поэтому он дешевле в эксплуатации, но восстанавливается дольше. Нельзя обещать архиву те же четыре секунды переключения, которые измерили у рабочего сервиса. В итоговом отчёте нужно указать оба режима и отдельно описать потерянные запросы. Ни одна подтверждённая покупка во время испытания не исчезла, однако три неподтверждённых запроса пришлось отправить заново.

### Критерии, зафиксированные до измерений

- Hot standby operational readiness, not physical heat; cold standby distinct
- 90 seconds outage versus four seconds failover
- Stable key is order deduplication identity, not encryption
- Split-brain permits writes on only one side; recover records before restoring primary
- No confirmed purchase lost, three unconfirmed requests retried; archive not promised four seconds

### Обычный режим

Первая содержательная часть 2.61 с; весь текст 9.80 с; подготовка 0.00 с (включена).

Server Reservation

In the new backup scheme, the second server operates in a "hot standby" mode. It receives copies of records but does not respond to user requests while the primary server is functioning properly. The term "hot standby" is not related to the temperature of the hardware. It means that the backup server is ready to quickly take over the workload without a full reinitialization of the data.

During the check, the primary server was disconnected from the network for 90 seconds. The backup server began responding after four seconds, and some clients resent their requests on their own. Two identical requests should not result in two identical purchases. Therefore, each order is assigned a permanent key, which is retained when resent. The key is used to identify the order, not to encrypt its content.

After restoring the connection, you cannot immediately consider the old primary server as the main one. First, you must compare the numbers of the last confirmed records and transfer any missing changes. If both servers start accepting new orders simultaneously and independently of each other, a data divergence will occur. In the instructions, such a scenario is referred to as a “cluster split”; during a “cluster split,” a record must be allowed by only one side.

A cold standby mode was selected for the separate archive: it is activated manually, making it cheaper to operate, but recovery takes longer. It is not possible to guarantee the same four-second switch-over time that was measured for the active service. The final report must specify both modes and separately describe the lost requests. No confirmed purchases were lost during the test; however, three unconfirmed requests had to be resent.


### Быстрый расширенный словарь

Первая содержательная часть 5.42 с; весь текст 13.49 с; подготовка 2.35 с (включена).

Server reservation

In the new reservation scheme, the second server operates in “hot standby” mode. It receives copies of the records but does not respond to user requests while the primary server is functional. The term “hot standby” is not related to the temperature of the hardware. It means that the backup server is ready to quickly take over the load without a full reload of the data.

During the check, the primary server was disconnected from the network for 90 seconds. The backup server began responding after four seconds, and some clients resent the request themselves. Two identical requests should not result in two identical purchases. Therefore, each order is assigned a permanent key, which is preserved when resent. The key is used to identify the order, not to encrypt its content.

After the connection is restored, the old primary server cannot be immediately considered the main one. First, it is necessary to compare the numbers of the last confirmed records and transfer any missing changes. If both servers start accepting new orders simultaneously and independently of each other, a data divergence will occur. In the instructions, such a scenario is referred to as a “cluster split”; during a “cluster split,” a record must be allowed by only one side.

A cold standby mode was selected for the separate archive: it is activated manually, making it cheaper to operate, but recovery takes longer. It is not possible to guarantee the same four-second switchover time for the archive that was measured for the active service. The final report must specify both modes and separately describe the lost requests. No confirmed purchases were lost during the test; however, three unconfirmed requests had to be resent.

Термины:

- разделением кластера → cluster split
- Резервирование → reservation
- сервера → server
- режиме → mode
- резерва → hot standby
- записей → records
- запросы → requests
- данных → data
- секунд → seconds
- покупки → purchase
## Полевой отчёт и местоимения — без кавычек

### Исходник

Измерения на реке

Марина приехала на исследовательскую станцию утром и сразу проверила журнал измерений. Она заметила, что вчерашние показания уровня воды записаны дважды. Коллега Павел решил, что один из датчиков неисправен, но Марина попросила не делать такой вывод до проверки времени записи. Оказалось, что один и тот же файл импортировали повторно. Датчики продолжали работать нормально.

После обеда они перенесли переносной прибор на правый берег. Правым считается берег справа по направлению течения, а не справа от человека, который смотрит на реку с моста. Марина осталась возле прибора, а Павел вернулся за аккумулятором. Она попросила его принести запасной кабель, потому что основной оказался слишком коротким. Сам прибор менять не требовалось.

В новой точке глубина составила 2,6 метра, на 0,4 метра больше, чем утром в предыдущей точке. Эти числа нельзя использовать как доказательство подъёма воды за день: измерения выполнены в разных местах. Для оценки изменения уровня нужно сравнивать показания одной и той же станции. Павел исправил черновик отчёта и убрал из него прежний вывод о наводнении.

К вечеру аккумулятор разрядился, и запись прекратилась на 12 минут. Пропущенные значения нельзя заменять нулями, потому что нулевое значение уровня имеет самостоятельный смысл. В таблице оставили отметку об отсутствии данных. Марина подготовила пояснение, а Павел проверил время перерыва. На следующий день они планируют повторить измерение в обеих точках и отдельно проверить резервное питание станции.

### Критерии, зафиксированные до измерений

- Marina is a woman/person, duplicate import not failed sensors
- Right bank defined downstream, not viewer's right from bridge
- Pavel retrieves battery and spare cable, retain instrument
- 2.6 m versus 0.4 m difference at distinct sites does not prove rise/flood
- 12-minute missing data not zero; removed flooding conclusion

### Обычный режим

Первая содержательная часть 2.73 с; весь текст 10.18 с; подготовка 0.00 с (включена).

Measurements on the river

Marina arrived at the research station in the morning and immediately checked the measurement log. She noticed that yesterday's water level readings had been recorded twice. Her colleague Pavel concluded that one of the sensors was malfunctioning, but Marina asked him not to jump to such a conclusion until they checked the recording timestamps. It turned out that the same file had been imported again. The sensors were still functioning normally.

After lunch, they moved the portable device to the right bank. The right bank is considered the one on the right side in the direction of the current, not the right side from the perspective of someone looking at the river from a bridge. Marina stayed near the device, while Pavel went back to get the battery. She asked him to bring a spare cable because the main one turned out to be too short. There was no need to replace the device itself.

At the new location, the depth was 2.6 meters, 0.4 meters more than in the previous location that morning. These figures cannot be used as evidence of a rise in water levels over the day, as the measurements were taken at different locations. To assess the change in water level, it is necessary to compare readings from the same station. Pavel revised the draft report and removed the previous conclusion about flooding.

By evening, the battery had run out, and the recording stopped for 12 minutes. The missing values cannot be replaced with zeros, because a zero level value has its own distinct meaning. A note indicating the absence of data was left in the table. Marina prepared an explanation, while Pavel checked the duration of the interruption. The next day, they plan to repeat the measurement at both points and separately test the station's backup power supply.


### Быстрый расширенный словарь

Первая содержательная часть 5.30 с; весь текст 12.75 с; подготовка 2.43 с (включена).

Measurements on the river

Marina arrived at the research station in the morning and immediately checked the measurement log. She noticed that yesterday’s water level readings were recorded twice. Her colleague Pavel concluded that one of the sensors was malfunctioning, but Marina asked him not to jump to such a conclusion before verifying the recording time. It turned out that the same file had been imported again. The sensors continued to function normally.

After lunch, they moved the portable device to the right bank. The right bank is considered the one on the right side of the current’s direction, not the right side from the perspective of someone looking at the river from a bridge. Marina stayed near the device, while Pavel went back to get the battery. She asked him to bring a spare cable because the main one turned out to be too short. There was no need to replace the device itself.

At the new location, the depth was 2.6 meters, 0.4 meters more than in the previous location in the morning. These figures cannot be used as evidence of a rise in water level over the day: the measurements were taken at different locations. To assess the change in level, it is necessary to compare the readings from the same station. Pavel revised the draft report and removed the previous conclusion about flooding.

By evening, the battery ran out, and the recording stopped for 12 minutes. The missing values cannot be replaced with zeros, because a zero level value has its own meaning. A note about the absence of data was left in the table. Marina prepared an explanation, and Pavel checked the duration of the interruption. The next day, they plan to repeat the measurement at both points and separately check the station’s backup power supply.

Термины:

- Марина → Marina
- Павел → Pavel
- станцию → station
- Измерения → measurements
- реке → river
- показания → readings
- уровня → level
- воды → water
- датчиков → sensors
- вывод → conclusion
## Диалог в гостинице — без кавычек

### Исходник

Изменение бронирования

Гость: Я забронировал номер с 12 по 15 июля на двоих. В подтверждении указаны две отдельные кровати, но на фотографии вижу одну большую. Мне важно уточнить это до оплаты остатка, потому что мы приезжаем с коллегой, а не с супругой.

Администратор: В вашем бронировании действительно две отдельные кровати. Фотография показывает другой вариант этой категории. Остаток оплаты составляет 180 евро; завтрак уже включён, доплачивать за него не нужно.

Гость: Тогда хочу изменить только дату приезда. Наш рейс перенесли, и мы попадём к вам после полуночи, уже 13 июля. Сохраните, пожалуйста, номер за нами на первую ночь. Это не просьба отменить ночь с 12 на 13 июля.

Администратор: Я отмечу позднее заселение. Бронирование по-прежнему начинается 12 июля, поэтому номер останется свободным для вас. Стойка регистрации работает круглосуточно. Если рейс снова задержат, напишите нам; автоматически отменять ваше бронирование мы не будем.

Гость: Спасибо. У коллеги аллергия на орехи. Можно ли предупредить кухню о завтраке на 13 июля? Я понимаю, что вы не можете гарантировать отсутствие всех следов орехов, поэтому прошу только передать информацию сотруднику кухни.

Администратор: Передам сообщение и попрошу сотрудника связаться с вами. Я не буду самостоятельно обещать безопасность каждого блюда. Также пришлю новое подтверждение позднего заселения. Сумма и дата выезда останутся прежними.

Гость: Хорошо. Подтвердите, пожалуйста, что доплата всё ещё 180 евро и выезд 15 июля. Мне нужен один документ для бухгалтерии, а не два отдельных счёта на каждого гостя.

### Критерии, зафиксированные до измерений

- Two separate beds, colleague not spouse; July 12–15
- 180 euros remaining, breakfast included
- After-midnight July 13 arrival retains paid July 12 night, not cancellation
- 24-hour reception; no automatic cancellation after further delay
- Allergy information passed on, no absolute safety guarantee; one invoice not two

### Обычный режим

Первая содержательная часть 2.11 с; весь текст 11.84 с; подготовка 0.00 с (включена).

Booking Change

Guest: I booked a room for two from July 12th to 15th. The confirmation mentions two separate beds, but the photo shows one large bed. It’s important for me to clarify this before paying the remaining balance, as I’m coming with a colleague, not my spouse.

Administrator: Your booking does indeed include two separate beds. The photograph shows a different variation of this room type. The remaining payment is 180 euros; breakfast is already included, so there’s no need to pay extra for it.

Guest: Then I'd like to change only the arrival date. Our flight has been rescheduled, and we'll arrive after midnight on July 13th. Please hold the room for us on the first night. This isn't a request to cancel the night of July 12th to 13th.

Administrator: I’ll note the late check-in. Your booking still starts on July 12, so the room will remain available for you. The front desk is open 24/7. If your flight is delayed again, please let us know; we won’t automatically cancel your booking.

Guest: Thank you. My colleague has a nut allergy. Could you please inform the kitchen about the breakfast on July 13th? I understand that you can’t guarantee the complete absence of any nut traces, so I’m just asking that you pass this information on to the kitchen staff.

Administrator: I'll pass on the message and ask the staff to contact you. I won't personally guarantee the safety of every dish. I'll also send a new confirmation for the late check-in. The amount and check-out date will remain the same.

Guest: Okay. Please confirm that the additional fee is still 180 euros and that the check-out is on July 15th. I need a single document for accounting purposes, not two separate invoices for each guest.


### Быстрый расширенный словарь

Первая содержательная часть 4.06 с; весь текст 13.80 с; подготовка 1.77 с (включена).

Booking modification

Guest: I booked a room for July 12–15 for two people. The confirmation lists two separate beds, but the photo shows one large bed. It’s important for me to clarify this before making the remaining payment, as we’re coming with a colleague, not my spouse.

Administrator: Your booking does indeed include two separate beds. The photo shows a different variation of this category. The remaining payment is 180 euros; breakfast is already included, so you don’t need to pay extra for it.

Guest: Then I’d like to change only the arrival date. Our flight has been rescheduled, and we’ll arrive after midnight on July 13. Please hold the room for us for the first night. This isn’t a request to cancel the night of July 12 to 13.

Administrator: I’ll note the late check-in. The booking still starts on July 12, so the room will remain available for you. The front desk is open 24/7. If your flight is delayed again, please let us know; we won’t automatically cancel your booking.

Guest: Thank you. My colleague has a nut allergy. Could you please inform the kitchen about the breakfast on July 13th? I understand that you can’t guarantee the complete absence of any nut traces, so I’m just asking that you pass this information on to the kitchen staff.

Administrator: I’ll forward the message and ask the staff member to contact you. I won’t personally guarantee the safety of every dish. I’ll also send a new late check-in confirmation. The amount and check-out date will remain the same.

Guest: Alright. Please confirm that the additional fee is still 180 euros and that the checkout is on July 15th. I need a single document for accounting purposes, not two separate invoices for each guest.

Термины:

- июля → July
- Гость → Guest
- номер → room
- бронирования → booking
- подтверждении → confirmation
- кровати → beds
- фотографии → photo
- оплаты → payment
- остатка → balance
- коллегой → colleague
## Диалог техподдержки — без кавычек

### Исходник

Восстановление доступа

Пользователь: После обновления приложение перестало показывать мои проекты. Я вижу пустой список, но папка с файлами на диске осталась. Не хочу начинать восстановление, которое сначала удалит эту папку. Можно ли проверить проблему без удаления данных?

Специалист: Да. Сначала откройте настройки и проверьте путь к папке проектов. Не нажимайте кнопку очистки. Обновление могло выбрать новый путь, поэтому пустой список ещё не означает, что старые файлы повреждены.

Пользователь: Путь действительно другой. Раньше папка находилась на внешнем диске, а сейчас указан внутренний. Я вернул старый путь, и появились 24 проекта из 25. Последний проект не открывается, хотя его файл виден в проводнике.

Специалист: Скопируйте только этот файл в отдельную папку и попробуйте открыть копию. Оригинал пока не меняйте. Если копия откроется, проверим права доступа к исходной папке. Если не откроется, посмотрим журнал ошибок; это ещё не основание удалять остальные проекты.

Пользователь: Копия открылась. В журнале есть сообщение об отказе в доступе к внешнему диску. Значит ли это, что нужно отключить защиту для всех приложений? Я бы предпочёл разрешить доступ только этому приложению.

Специалист: Отключать общую защиту не требуется. Выдайте этому приложению доступ к выбранной папке через системное окно. После этого закройте копию и проверьте оригинал. Сохраните резервную копию до завершения проверки.

Пользователь: Теперь оригинал тоже открывается, и видны все 25 проектов. Копию пока оставлю. Подтвердите, что обновление не переносило сами файлы на внутренний диск, а изменило только путь, по которому приложение их искало.

### Критерии, зафиксированные до измерений

- Do not delete original folder/data or press cleanup
- Path changed, not proof of corrupted files
- 24 of 25 then all 25 projects; test copy before modifying original
- No global protection disable; grant this app selected-folder access
- Final user asks confirmation, must not become an unsupported affirmative claim

### Обычный режим

Первая содержательная часть 2.03 с; весь текст 11.57 с; подготовка 0.00 с (включена).

Restore Access

User: After the update, the app stopped showing my projects. I see an empty list, but the folder containing the files on my disk is still there. I don’t want to start a recovery process that might delete this folder first. Is it possible to troubleshoot the issue without deleting my data?

Specialist: Yes. First, open the settings and check the project folder path. Do not press the clear button. The update might have selected a new path, so an empty list doesn't necessarily mean the old files are corrupted.

User: The path is indeed different. Previously, the folder was on an external drive, but now it's pointing to an internal one. I reverted to the old path, and 24 out of 25 projects reappeared. The last project won't open, even though its file is visible in File Explorer.

Specialist: Copy only this file to a separate folder and try opening the copy. Do not modify the original for now. If the copy opens, we’ll check the access permissions for the original folder. If it doesn’t open, we’ll review the error log; this is not yet a reason to delete the other projects.

User: The copy has opened. There's a message in the log about access being denied to an external drive. Does this mean I need to disable protection for all applications? I'd prefer to allow access only for this specific application.

Specialist: There is no need to disable the general protection. Grant this application access to the selected folder through the system window. After that, close the copy and check the original. Save the backup before completing the verification.

User: Now the original file is also opening, and all 25 projects are visible. I’ll leave the copy for now. Please confirm that the update didn’t move the files themselves to the internal drive, but only changed the path the app was using to locate them.


### Быстрый расширенный словарь

Первая содержательная часть 4.51 с; весь текст 14.77 с; подготовка 2.23 с (включена).

Recovery of access

User: After the update, the application stopped showing my projects. I see an empty list, but the folder containing the files on the disk is still there. I don’t want to start the Recovery process, which would first delete this folder. Is it possible to check the issue without deleting the data?

Specialist: Yes. First, open the settings and check the path to the projects folder. Do not press the clear button. The update might have selected a new path, so an empty list does not yet mean that the old files are corrupted.

User: The path is indeed different. Previously, the folder was on an external drive, but now an internal one is specified. I reverted to the old path, and 24 out of 25 projects have reappeared. The last project won’t open, although its file is visible in File Explorer.

Specialist: Copy only this file into a separate folder and try to open the copy. Do not change the original for now. If the copy opens, we’ll check the access permissions for the original folder. If it doesn’t open, we’ll look at the error log; this is not yet a reason to delete the other projects.

User: The copy opened. There's a message in the log about access being denied to an external drive. Does this mean I need to disable protection for all applications? I would prefer to grant access only to this application.

Specialist: There is no need to disable the general protection. Grant this application access to the selected folder through the system window. After that, close the copy and check the original. Save the backup before completing the verification.

User: Now the original also opens, and all 25 projects are visible. I’ll leave the copy for now. Confirm that the update didn’t move the files themselves to the internal drive, but only changed the path the application used to locate them.

Термины:

- папка → folder
- проекты → projects
- копию → copy
- Восстановление → Recovery
- доступа → access
- Пользователь → User
- обновления → update
- приложение → application
- список → list
- файлами → files
## Счёт и ключ — смена значений без кавычек

### Исходник

Разные значения в разговоре

Организатор: Отель прислал счёт за аренду зала. Проверьте счёт до оплаты: там почему-то указаны 18 участников, хотя мы подтвердили только 16. Если это ошибка, попросите исправленный документ, но пока не переводите деньги.

Помощник: Проверю. Ещё бухгалтер просит номер банковского счёта получателя. Это тот же номер, что напечатан вверху счёта за зал, или отдельный реквизит? Я не хочу перепутать номер документа с номером банковского счёта.

Организатор: Это разные номера. Счёт за услуги содержит номер документа, а банковский счёт — реквизит для перевода денег. Сверьте реквизит с договором, а сумму — с исправленным счётом. Только после обеих проверок можно платить.

Помощник: Понятно. Кстати, команда уже закончила матч? На табло был счёт 2:1, но связь пропала перед финальным свистком. Мне нужен окончательный счёт матча для объявления, а не сумма из финансового документа.

Организатор: Матч завершился со счётом 2:2. Объявите ничью. После объявления заберите ключ от кладовой у администратора. Запасной ключ лежит в запечатанном конверте, открывать его без разрешения не нужно.

Помощник: Музыкант тоже спрашивал про ключ, но имел в виду знак в начале нотной строки. Он просит распечатать партию в басовом ключе, потому что вариант в скрипичном ключе ему неудобен. К кладовой его просьба не относится.

Организатор: Тогда передайте музыканту нужные ноты, а физический ключ верните администратору после разгрузки. Не отправляйте фотографию ключа в общий чат. Финансовые документы, результат матча и ноты положите в три отдельные папки.

### Критерии, зафиксированные до измерений

- Invoice for hall, bank account and match score remain distinct meanings of schet
- Invoice number differs from bank account; verify account against contract and amount against corrected invoice
- 18 vs 16 participants; provisional 2:1 versus final 2:2 draw
- Physical door key distinguished from bass/treble musical clef
- Do not open spare-key envelope without permission or send key photo; three separate folders

### Обычный режим

Первая содержательная часть 1.98 с; весь текст 11.57 с; подготовка 0.00 с (включена).

Different meanings in conversation

Organizer: The hotel has sent an invoice for the hall rental. Please check the invoice before payment: it somehow lists 18 participants, although we only confirmed 16. If this is an error, request a corrected document, but do not make the payment yet.

Assistant: Let me check. The accountant is also asking for the recipient's bank account number. Is this the same number printed at the top of the hall invoice, or is it a separate detail? I don't want to confuse the document number with the bank account number.

Organizer: These are different numbers. The service invoice contains a document number, while the bank account details are for transferring money. Verify the account details against the contract and the amount against the corrected invoice. You can only make the payment after both checks are completed.

Assistant: Understood. By the way, has the team already finished the match? The score on the scoreboard was 2:1, but the connection was lost before the final whistle. I need the final match score for the announcement, not the total from the financial document.

Organizer: The match ended with a score of 2:2. Declare a draw. After the declaration, collect the storage room key from the administrator. The spare key is in a sealed envelope; do not open it without permission.

Assistant: The musician also asked about the key, but they were referring to the symbol at the beginning of the musical staff. They want the part printed in bass clef because the treble clef version is inconvenient for them. Their request has nothing to do with the storeroom.

Organizer: Then, pass the necessary sheet music to the musician, and return the physical key to the administrator after unloading. Do not send a photo of the key to the general chat. Place the financial documents, match results, and sheet music into three separate folders.


### Быстрый расширенный словарь

Первая содержательная часть 4.56 с; весь текст 15.15 с; подготовка 2.42 с (включена).

Different meanings in conversation

Organizer: The hotel sent an invoice for the hall rental. Please check the invoice before payment: it somehow lists 18 participants, although we only confirmed 16. If this is an error, request a corrected document, but do not transfer the money yet.

Assistant: Let me check. The accountant is also asking for the recipient’s bank account number. Is this the same number printed at the top of the invoice, or is it a separate detail? I don’t want to confuse the document number with the bank account number.

Organizer: These are different numbers. The service invoice contains the document number, while the bank account provides the details for transferring money. Verify the details against the contract, and the amount against the corrected invoice. You can only make the payment after both checks are completed.

Assistant: Understood. By the way, has the team already finished the match? The score on the board was 2:1, but the connection was lost before the final whistle. I need the final score of the match for the announcement, not the amount from the financial document.

Organizer: The match ended with a score of 2:2. Declare a draw. After the declaration, collect the storage room key from the administrator. The spare key is in a sealed envelope; there is no need to open it without permission.

Assistant: The musician also asked about the key, but they were referring to the symbol at the beginning of the musical staff. They want the part printed in bass clef because the treble clef version is inconvenient for them. Their request has nothing to do with the storeroom.

Organizer: Then, pass the necessary sheet music to the musician, and return the physical key to the administrator after unloading. Do not send a photo of the key to the general chat. Place the financial documents, the match result, and the sheet music into three separate folders.

Термины:

- счёт → invoice
- ключ → key
- номер → number
- документ → document
- Организатор → Organizer
- деньги → money
- Помощник → Assistant
- реквизит → details
- сумму → amount
- матч → match
