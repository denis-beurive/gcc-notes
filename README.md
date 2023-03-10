# Notes about GCC and related tools or files

## GCC

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

Get the compiler list of search paths for headers and libraries:

```bash
echo | gcc -E -Wp,-v - | grep -v "# "
```

> * `-E`: Stop after the preprocessing stage; do not run the compiler proper. The output is in the form of preprocessed source code, which is sent to the standard output. Input files which don't require preprocessing are ignored.
> * `-Wp,option`: You can use `-Wp,option` to bypass the compiler driver and pass option directly through to the preprocessor. 

# Dynamic linker LD

Print the linker search directories:

```bash
ld --verbose | grep SEARCH_DIR | tr -s ' ;' \\012
```

Add search paths for dynamic libraries once and for all (as `root`):

```bash
echo "/usr/local/lib" > /etc/ld.so.conf.d/odpic.conf
rm -f /etc/ld.so.cache && ldconfig
```

> You can set the path to a dynamic library temporarily: `export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/local/lib`.

## Makefile

Sometimes, you need to disable all optimisations in an executable built using a `configure` script. This is the case, for example, if you plan to use GDB.

This line may help:

```bash
find ./ -name Makefile -exec sed -E -i "s/^(C(XX)?FLAGS\\s*=.*)(-O[1-9])(\\s+(.*))?$/\1-O0\4/" {} \;
find ./ -name Makefile -exec grep -E "^C(XX)?FLAGS\\s*=" {} \;
```

Tests:

```bash
$ echo "CFLAGS=-g -O2" | sed -E "s/^(C(XX)?FLAGS\\s*=.*)(-O[1-9])(\\s+(.*))?$/\1-O0\4/"
CFLAGS=-g -O0

$ echo "CXXFLAGS=-g -O2" | sed -E "s/^(C(XX)?FLAGS\\s*=.*)(-O[1-9])(\\s+(.*))?$/\1-O0\4/"
CFLAGS=-g -O0

$ echo "CFLAGS=-g -O2 #other options" | sed -E "s/^(C(XX)?FLAGS\\s*=.*)(-O[1-9])(\\s+(.*))?$/\1-O0\4/"
CFLAGS=-g -O0 #other options

$ echo "CFLAGS=-O2 #other options" | sed -E "s/^(C(XX)?FLAGS\\s*=.*)(-O[1-9])(\\s+(.*))?$/\1-O0\4/"
CFLAGS=-O0 #other options
```

