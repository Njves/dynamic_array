from setuptools import setup
from Cython.Build import cythonize

# python setup.py build_ext --inplace
setup(
    name='carray.pyx',
    ext_modules=cythonize("carray.pyx"),
    zip_safe=False,
)