# cython: language_level=3
# distutils: language = c

# Указываем компилятору, что используется Python 3 и целевой формат
# языка Си (во что компилируем, поддерживается Си и C++)


# Также понадобятся функции управления памятью
from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free

# Для преоразования Python объекта float в Сишный тип и обратно
from cpython.float cimport PyFloat_FromDouble, PyFloat_AsDouble
from cpython.long cimport PyLong_FromLong, PyLong_AsLong
import array as py_array
import math


# Так как хотим использовать массив для разных типов, указывая только
# код типа без дополнительных замарочек, то используем самописный
# дескриптор. Он будет хранить функции получения и записи значения в
# массив для нужных типов. Упрощенны аналог дескриптора из модуля array:
# https://github.com/python/cpython/blob/243b6c3b8fd3144450c477d99f01e31e7c3ebc0f/Modules/arraymodule.c#L32
cdef struct arraydescr:
    # код типа, один символ
    char* typecode
    # размер одного элемента массива
    int itemsize
    # функция получения элемента массива по индексу. Обратите внимание,
    # что она возвращает Python тип object. Вот так выглядит сигнатура на Си:
    # PyObject * (*getitem)(struct arrayobject *, Py_ssize_t)
    object (*getitem)(array, size_t)
    # функция записи элемента массива по индексу. Третий аргумент это
    # записываемое значение, оно приходит из Python. Сигнатура на Си:
    # int (*setitem)(struct arrayobject *, Py_ssize_t, PyObject *)
    int (*setitem)(array, size_t, object)


cdef object double_getitem(array a, size_t index):
    # Функция получения значения из массива для типа double.
    # Обратите внимание, что Cython сам преобразует Сишное значение типа
    # double в аналогичны объект PyObject
    return (<double *> a.data)[index]


cdef int double_setitem(array a, size_t index, object obj):
    # Функция записи значения в массив для типа double. Здесь нужно
    # самими извлеч значение из объекта PyObject.
    if not isinstance(obj, int) and not isinstance(obj, float):
        return -1

    # Преобразования Python объекта в Сишный
    cdef double value = PyFloat_AsDouble(obj)

    if index >= 0:
        # Не забываем преобразовывать тип, т.к. a.data имеет тип char
        (<double *> a.data)[index] = value
    return 0

cdef object long_getitem(array a, size_t index):
    # Функция получения значения из массива для типа long.
    # Обратите внимание, что Cython сам преобразует Сишное значение типа
    # long в аналогичны объект PyObject
    return (<long *> a.data)[index]


cdef int long_setitem(array a, size_t index, object obj):
    # Функция записи значения в массив для типа long. Здесь нужно
    # самими извлеч значение из объекта PyObject.
    if not isinstance(obj, int):
        return -1

    # Преобразования Python объекта в Сишный
    cdef long value = PyLong_AsLong(obj)

    if index >= 0:
        # Не забываем преобразовывать тип, т.к. a.data имеет тип char
        (<long *> a.data)[index] = value
    return 0


# Если нужно работать с несколькими типами используем массив дескрипторов:
# https://github.com/python/cpython/blob/243b6c3b8fd3144450c477d99f01e31e7c3ebc0f/Modules/arraymodule.c#L556
cdef arraydescr[2] descriptors = [
    arraydescr("d", sizeof(double), double_getitem, double_setitem),
    arraydescr("i", sizeof(long), long_getitem, long_setitem)
]


# Зачатки произвольных типов, значения - индексы дескрипторов в массиве
cdef enum TypeCode:
    DOUBLE = 0
    LONG = 1


# преобразование строкового кода в число
cdef int char_typecode_to_int(str typecode):
    if typecode == "d":
        return TypeCode.DOUBLE
    if typecode == "i":
        return TypeCode.LONG
    return -1

# нормализируем индекс массива
cdef int normalize_index(int index, int length):
    if length > 0:
        if index < 0:
            if abs(index) > length:
                index = 0
            else:
                index = index % length
        elif index >= length:
            index = length
        return index
    raise IndexError()

def get_required_memory(size_t length):
    return 2 * length

def is_allocate_memory(size_t length, size_t capacity):
    return length >= capacity

cdef class array:
    # Класс статического массива.
    # В поле length сохраняем длину массива, а в поле data будем хранить
    # данные. Обратите внимание, что для data используем тип char,
    # занимающий 1 байт. Далее мы будем выделять сразу несколько ячеек
    # этого типа для одного значения другого типа. Например, для
    # хранения одного double используем 8 ячеек для char.
    cdef public size_t length
    cdef char* data
    cdef arraydescr* descr
    cdef size_t capacity

    # Аналог метода __init__
    def __cinit__(self, str typecode, list init):
        self.length = len(init)
        self.capacity = get_required_memory(self.length)
        if typecode != 'd' and typecode != 'i':
            raise TypeError("Код может быть либо d или i")
        cdef int mtypecode = char_typecode_to_int(typecode)
        self.descr = &descriptors[mtypecode]

        # Выделяем память для массива
        self.data = <char*> PyMem_Malloc(self.capacity * self.descr.itemsize)
        if not self.data:
            raise MemoryError()
        cdef i = 0
        for i in range(len(init)):
            self.__setitem__(i, init[i])


    # Не забываем освобаждать память. Привязываем это действие к объекту
    # Python. Это позволяет освободить память во время сборки мусора.
    def __dealloc__(self):
        PyMem_Free(self.data)

    # Пользовательски метод для примера. Инициализация массива числами
    # от 0 до length. В Cython можно использовать функции из Python,
    # они преобразуются в Сишные аналоги.
    def initialize(self):
        # Объявление переменно цикла позволяет эффективнее комплировать код.
        cdef int i

        for i in range(self.length):
            if self.descr.typecode == b"d":
                self.__setitem__(i, PyFloat_FromDouble(<double> i))
            if self.descr.typecode == b"i":
                self.__setitem__(i, PyLong_FromLong(<long> i))

    # проверяет входит ли индекс в интервал массива
    def check_index(self, int index):
        return 0 <= index < self.length

    def get_absolute_index(self, object index):
        return self.length - abs(index)


    # возвращает элементы по индексу
    def __getitem__(self, object index):
        if not isinstance(index, int) or index % 1 != 0 :
            raise TypeError("Индекс должен быть целым числом")
        else:
            index = int(index)
        if not isinstance(index, int):
            raise TypeError("Индексация производится только с целыми числами")
        if index < 0:
            index = self.get_absolute_index(index)
        if self.check_index(index):
            return self.descr.getitem(self, index)
        raise IndexError("array index out of range")

    # записывает элементы в массив по индексу
    def __setitem__(self, int index, object value):
        if self.check_index(index):
            if index < 0:
                index = self.get_absolute_index(index)
            self.descr.setitem(self, index, value)
        else:
            raise IndexError()



    # добавляет новый элемент в конец массива
    def append(self, object value):
        if isinstance(value, float) and self.descr.typecode == b'i':
            if value % 1 != 0:
                raise TypeError('Неверный тип должен быть integer')

        if is_allocate_memory(self.length, self.capacity):
            self.capacity = get_required_memory(self.length)
            self.data = <char*> PyMem_Realloc(self.data, self.capacity * self.descr.itemsize)
        self.length += 1
        self.__setitem__(self.length - 1, value)

    # добавляет новый элемент массива по индексу
    def insert(self, int index, object value):
        if index < 0 or index > self.length:
            index = normalize_index(index, self.length)

        self.length += 1 # 3

        if is_allocate_memory(self.length, self.capacity):
            self.capacity = get_required_memory(self.length)
            self.data = <char*> PyMem_Realloc(self.data, self.capacity * self.descr.itemsize)

        cdef int i
        for i in range(self.length - 1, index, -1):
            self.__setitem__(i, self.__getitem__(i - 1))
        self.__setitem__(index, value)




    def remove(self, object value):
        cdef int i = 0
        cdef removed_index = 0
        cdef int is_match_value = 0
        for i in range(self.length):
            if self.__getitem__(i) == value:
                is_match_value = 1
                index = i
                break
        if is_match_value == 0:
            raise ValueError("Удаляемое значение не найдено")

        cdef int j = index
        for j in range(index, self.length - 1):
            self.__setitem__(j, self.__getitem__(j + 1))
        self.length -= 1
        if self.capacity * 0.33 > self.length:
            self.capacity /= 2
            self.data = <char *> PyMem_Realloc(self.data, self.capacity * self.descr.itemsize)


    # удаляет элемент первого вхождения и возвращает его
    def pop(self, int index):
        if index < 0:
            if abs(index) > self.length:
                raise IndexError()
            else:
                index = normalize_index(index, self.length)
        if index >= self.length:
            raise IndexError()

        cdef double returned_value = self.__getitem__(index)
        cdef int j = index
        for j in range(index, self.length - 1):
            self.__setitem__(j, self.__getitem__(j + 1))
        self.length -= 1

        if self.capacity * 0.33 > self.length:
            self.capacity /= 2
            self.data = <char *> PyMem_Realloc(self.data, self.capacity * self.descr.itemsize)
        if self.descr.typecode == b'i':
            return int(returned_value)
        if self.descr.typecode == b'd':
            return float(returned_value)

    # разворачивает массив
    def __reversed__(self):
        cdef i = 0
        for i in range(self.length):
            yield self.descr.getitem(self, self.length - i - 1)

    def __eq__(self, other):
        if isinstance(other, py_array.array):
            if other.typecode.encode('utf-8') == self.descr.typecode:
                if list(self) == list(other):
                    return True
        return False

    # создает строчнео представление массива
    def __str__(self):
        string = "["
        cdef i = 0
        for i in range(self.length):
            if i == self.length - 1:
                string += str(self.descr.getitem(self, i))
                continue
            string += str(self.descr.getitem(self, i)) + ", "
        string += "]"
        return string

    # печатает массив
    def __repr__(self):
        return str(self)

    # возвращает длину массива
    def __len__(self):
        return self.length

    # определяет занимаемый размер массива в байтах.
    def __sizeof__(self):
        return self.capacity * self.descr.itemsize



