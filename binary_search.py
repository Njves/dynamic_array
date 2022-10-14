"""
Модуль содержащий реализацию алгоритма бинарного
поиска в массиве
"""


def search(sequence: list, item: float):
    """
    Выполняет бинарный поиск по списку
    :param sequence: массив данных
    :param item: искомое значение
    :return: индекс найденного элемента
    """
    if len(sequence) == 0:
        return None
    mid = len(sequence) // 2
    low = 0
    high = len(sequence) - 1

    while sequence[mid] != item and low <= high:
        if item >= sequence[mid]:
            if abs(low - mid) != 1:
                low = mid + 1
            else:
                low = mid
        else:
            if abs(high - mid) != 1:
                high = mid - 1
            else:
                high = mid
        mid = (low + high) // 2

    if abs(low - high) <= 2 and low < len(sequence) - 1:
        if sequence[low] == item:
            mid = low
    if low > high:
        return None
    return mid
