# Notes about GCC

Compiling a source code provided through the standard input:

```bash
echo "int main(){return 0;}" | gcc -xc -
```

> This trick can be used to test a compiler toolchain within a script.

Testing whether a header file (here "`dpi.h`") can be found or not:

```bash
echo "#include <dpi.h>"$'\n'"int main(){return 0;}" | gcc -xc -
```

> Please note the use of `$'\n'` (this is the sequence of characters to print a new line with _Bash_).
>
> This trick can be used to test whether a build environment is well configured or not within a script.

Testing whether a library (here "`libodpic.so`") can be found or not:

```bash
echo "int main(){return 0;}" | gcc -xc -lodpic -
```

> This trick can be used to test whether a build environment is well configured or not within a script.
