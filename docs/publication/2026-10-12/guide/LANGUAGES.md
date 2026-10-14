# Языковой каталог и границы покрытия

Извлечено из `shared/packages/OfflineCore/Sources/OfflineCore/LanguageSelection.swift` на 12.10.2026: 152 строк общего справочника; 150 доступных записей Index, 4 языка OPUS. [CSV](../evidence/language-catalog.csv).

OPUS даёт только English ↔ Russian/Ukrainian/Belarusian: четыре языка означают шесть направлений, не двенадцать. Для Index список содержит языки/варианты; это не 150 проверенных speech-to-speech пар.

`Whisper_code` означает наличие кода в каталоге, `voice_catalog_flag` — флаг каталога, не подтверждённый установленный голос или его коммерческую пригодность. Реальный выбранный голос, пакет, runtime и лицензия проверяются отдельно. OCR зависит от платформы и ОС; универсального обещания OCR для всего списка нет. Android GigaAM/Parakeet routing задаётся отдельным каталогом `assets/catalogs/android-asr.json`.

| Код | Русский | English | Index | OPUS | Whisper |
|---|---|---|---|---|---|
| en | Английский | English | да | да | en |
| zh | Китайский | Chinese | да | — | zh |
| de | Немецкий | German | да | — | de |
| fr | Французский | French | да | — | fr |
| es | Испанский | Spanish | да | — | es |
| ja | Японский | Japanese | да | — | ja |
| ko | Корейский | Korean | да | — | ko |
| pt | Португальский | Portuguese | да | — | pt |
| ru | Русский | Russian | да | да | ru |
| ar | Арабский | Arabic | да | — | ar |
| it | Итальянский | Italian | да | — | it |
| nl | Нидерландский | Dutch | да | — | nl |
| pl | Польский | Polish | да | — | pl |
| ro | Румынский | Romanian | да | — | ro |
| sv | Шведский | Swedish | да | — | sv |
| tr | Турецкий | Turkish | да | — | tr |
| hi | Хинди | Hindi | да | — | hi |
| vi | Вьетнамский | Vietnamese | да | — | vi |
| th | Тайский | Thai | да | — | th |
| id | Индонезийский | Indonesian | да | — | id |
| ms | Малайский | Malay | да | — | ms |
| tl | Тагальский | Filipino | да | — | tl |
| uk | Украинский | Ukrainian | да | да | uk |
| fa | Персидский | Persian | да | — | fa |
| cs | Чешский | Czech | да | — | cs |
| el | Греческий | Greek | да | — | el |
| da | Датский | Danish | да | — | da |
| hu | Венгерский | Hungarian | да | — | hu |
| fi | Финский | Finnish | да | — | fi |
| no | Норвежский (букмол) | Norwegian Bokmål | да | — | no |
| sk | Словацкий | Slovak | да | — | sk |
| bg | Болгарский | Bulgarian | да | — | bg |
| bs | Боснийский | Bosnian | да | — | bs |
| ca | Каталанский | Catalan | да | — | ca |
| bn | Бенгальский | Bengali | да | — | bn |
| he | Иврит | Hebrew | да | — | he |
| lt | Литовский | Lithuanian | да | — | lt |
| sl | Словенский | Slovenian | да | — | sl |
| et | Эстонский | Estonian | да | — | et |
| sq | Албанский | Albanian | да | — | sq |
| lv | Латышский | Latvian | да | — | lv |
| az | Азербайджанский | Azerbaijani | да | — | az |
| hr | Хорватский | Croatian | да | — | hr |
| ta | Тамильский | Tamil | да | — | ta |
| ne | Непальский | Nepali | да | — | ne |
| ur | Урду | Urdu | да | — | ur |
| mk | Македонский | Macedonian | да | — | mk |
| sr | Сербский (кириллица) | Serbian (Cyrillic) | да | — | sr |
| mr | Маратхи | Marathi | да | — | mr |
| ka | Грузинский | Georgian | да | — | ka |
| ml | Малаялам | Malayalam | да | — | ml |
| kk | Казахский | Kazakh | да | — | kk |
| is | Исландский | Icelandic | да | — | is |
| gl | Галисийский | Galician | да | — | gl |
| kn | Каннада | Kannada | да | — | kn |
| ary | Арабский (марокканский) | Moroccan Arabic | да | — | — |
| gu | Гуджарати | Gujarati | да | — | gu |
| be | Белорусский | Belarusian | да | да | be |
| af | Африкаанс | Afrikaans | да | — | af |
| hy | Армянский | Armenian | да | — | hy |
| mn | Монгольский | Mongolian | да | — | mn |
| km | Кхмерский | Khmer | да | — | km |
| eu | Баскский | Basque | да | — | eu |
| my | Бирманский | Burmese | да | — | my |
| la | Латинский | Latin | да | — | la |
| uz-Cyrl | Узбекский (кириллица) | Uzbek (Cyrillic) | да | — | — |
| te | Телугу | Telugu | да | — | te |
| or | Ория | Odia | да | — | — |
| nn | Норвежский (нюнорск) | Norwegian Nynorsk | да | — | nn |
| uz | Узбекский | Uzbek | да | — | uz |
| sw | Суахили | Swahili | да | — | sw |
| si | Сингальский | Sinhala | да | — | si |
| ky | Киргизский | Kyrgyz | да | — | — |
| so | Сомалийский | Somali | да | — | so |
| pa | Панджаби | Punjabi | да | — | pa |
| arz | Арабский (египетский) | Egyptian Arabic | да | — | — |
| cy | Валлийский | Welsh | да | — | cy |
| nrm | Нормандский | Norman | да | — | — |
| ps | Пушту | Pashto | да | — | ps |
| ga | Ирландский | Irish | да | — | — |
| sr-Latn | Сербский (латиница) | Serbian (Latin) | да | — | — |
| ha | Хауса | Hausa | да | — | ha |
| ckb | Курдский (сорани) | Central Kurdish | да | — | — |
| mt | Мальтийский | Maltese | да | — | mt |
| yue | Кантонский | Cantonese | да | — | yue |
| tg | Таджикский | Tajik | да | — | tg |
| ku | Курдский (курманджи) | Northern Kurdish | да | — | — |
| bew | Бетави | Betawi | да | — | — |
| am | Амхарский | Amharic | да | — | am |
| lo | Лаосский | Lao | да | — | lo |
| lb | Люксембургский | Luxembourgish | да | — | lb |
| fy | Фризский | Frisian | да | — | — |
| dv | Дивехи | Dhivehi | да | — | — |
| eo | Эсперанто | Esperanto | да | — | — |
| rw | Киньяруанда | Kinyarwanda | да | — | — |
| ars | Арабский (недждийский) | Najdi Arabic | да | — | — |
| fo | Фарерский | Faroese | да | — | fo |
| mg | Малагасийский | Malagasy | да | — | mg |
| as | Ассамский | Assamese | да | — | as |
| sd | Синдхи | Sindhi | да | — | sd |
| xh | Коса | Xhosa | да | — | — |
| tk | Туркменский | Turkmen | да | — | tk |
| ht | Гаитянский креольский | Haitian Creole | да | — | ht |
| gd | Шотландский гэльский | Scottish Gaelic | да | — | — |
| ceb | Себуанский | Cebuano | да | — | — |
| yi | Идиш | Yiddish | да | — | yi |
| jv | Яванский | Javanese | да | — | jw |
| ba | Башкирский | Bashkir | да | — | ba |
| pap | Папьяменто | Papiamento | да | — | — |
| mi | Маори | Māori | да | — | mi |
| ug | Уйгурский | Uyghur | да | — | — |
| tt | Татарский | Tatar | да | — | tt |
| bo | Тибетский | Tibetan | да | — | bo |
| mww | Хмонг-дау | Hmong Daw | да | — | — |
| hyw | Западноармянский | Western Armenian | да | — | — |
| yo | Йоруба | Yoruba | да | — | yo |
| zu | Зулу | Zulu | да | — | — |
| sdh | Курдский (южный) | Southern Kurdish | да | — | — |
| sm | Самоанский | Samoan | да | — | — |
| co | Корсиканский | Corsican | да | — | — |
| hif | Фиджийский хинди | Fiji Hindi | да | — | — |
| su | Сунданский | Sundanese | да | — | su |
| ny | Ньянджа | Chichewa | да | — | — |
| ig | Игбо | Igbo | да | — | — |
| haw | Гавайский | Hawaiian | да | — | haw |
| st | Сесото | Sesotho | да | — | — |
| lus | Мизо | Mizo | да | — | — |
| sn | Шона | Shona | да | — | sn |
| cv | Чувашский | Chuvash | да | — | — |
| azb | Азербайджанский (южный) | South Azerbaijani | да | — | — |
| rm | Романшский | Romansh | да | — | — |
| rn | Кирунди | Rundi | да | — | — |
| hi-Latn | Хинди (латиница) | Hindi (Latin) | да | — | — |
| sah | Якутский | Yakut | да | — | — |
| ti | Тигринья | Tigrinya | да | — | — |
| ast | Астурийский | Asturian | да | — | — |
| oc | Окситанский | Occitan | да | — | oc |
| cnh | Чинский (хака) | Hakha Chin | да | — | — |
| se | Северносаамский | Northern Sami | да | — | — |
| nds | Нижненемецкий | Low German | да | — | — |
| os | Осетинский | Ossetian | да | — | — |
| ur-Latn | Урду (латиница) | Urdu (Latin) | да | — | — |
| gsw | Швейцарский немецкий | Swiss German | да | — | — |
| anp | Анги́ка | Angika | да | — | — |
| apc | Арабский (левантийский) | Levantine Arabic | да | — | — |
| om | Оромо | Oromo | да | — | — |
| nap | Неаполитанский | Neapolitan | да | — | — |
| hsb | Верхнелужицкий | Upper Sorbian | да | — | — |
| hil | Хилигайнон | Hiligaynon | да | — | — |
| kl | Гренландский | Greenlandic | да | — | — |
| ban | Балийский | Balinese | — | — | — |
| zh-Hant | Китайский (традиционный) | Chinese (Traditional) | — | — | — |
