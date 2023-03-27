# Notes about GCC and related tools or files

## GCC

### Environment discovery

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

### Compilation

It is highly recommended to set these compilation flags:

```
-Wall -Wuninitialized -Wmissing-include-dirs -Wextra -Wconversion -Werror -Wfatal-errors -Wformat
```

However, these flags will likely trigger warning that should (and often _must_) be ignored.

Suppress a warning for a single line of code:

```c
#pragma GCC diagnostic ignored "-Wuninitialized"
```

> See [this link](https://gcc.gnu.org/onlinedocs/gcc/Warning-Options.html) for a list of warnings to suppress.

## Dynamic linker LD

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

## Using Valgrind

```bash
$ valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all -s ./bin/program.exe
...
==30454==
==30454== HEAP SUMMARY:
==30454==     in use at exit: 0 bytes in 0 blocks
==30454==   total heap usage: 162,732 allocs, 162,732 frees, 8,480,050 bytes allocated
==30454==
==30454== All heap blocks were freed -- no leaks are possible
==30454==
==30454== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)
```

## Using "const"

```c
const char c1
```

You cannot modify the value of `c1`.

```c
const char *c2
```

You cannot modify the content of the memory pointed by `c2`.
However, you can modify the value of `c2` (the address of the pointed memory location).

```c
char* const c3
```

You cannot modify the value of `c3` (the address of the pointed memory location).
However, you can modify the content of the memory location pointed by `c3`.

```c
const char* const c4
```

You cannot modify the value of `c4` (the address of the pointed memory location).
And, you cannot modify the content of the memory pointed by `c4`.


**Illustration**:

```c
char* set_value(const char* const in_string) {
    char *c = (char*) malloc(sizeof(char) * (strlen(in_string) + 1));
    strcpy(c, in_string);
    return c;
}

void example2() {
    // You cannot modify the value of `c1`.
    const char c1 = 60;

    // You cannot modify the content of the memory pointed by `c2`.
    // However, you can modify the value of `c2` (the address of the pointed memory location).
    // NOTE: for this example, we do not initialize the value of `c2` with a constant (ex: `const char *c2 = "abc"`).
    //       Indeed, in this case, the memory would be allocated in a memory write-protected area
    //       (the area that contains the executable's code).
    const char *c2 = set_value("123");

    // You cannot modify the value of `c3` (the address of the pointed memory location).
    // However, you can modify the content of the memory location pointed by `c3`.
    // NOTE: do not try to initialize the value of `c3` with a constant (ex: `char* const c3 = "abc"`).
    //       Indeed, in this case, the memory would be allocated in a memory write-protected area
    //       (the area that contains the executable's code).
    char* const c3 = set_value("abc");

    // You cannot modify the value of `c4` (the address of the pointed memory location).
    // And, you cannot modify the content of the memory pointed by `c4`.
    const char* const c4 = set_value("def");

    // You cannot modify the value of `c1`.
    printf("c1 = %c\n", c1);

    // You cannot modify the content of the memory pointed by `c2`.
    // However, you can modify the value of `c2`.
    printf("c2 = %s\n", c2);
    c2 = set_value("new address");
    printf("c2 = %s\n", c2);

    // You cannot modify the value of `c3`.
    // However, you can modify the content of the memory pointed by `c3`.
    printf("c3 = %s\n", c3);
    *c3 = '1';
    *(c3+1) = '2';
    *(c3+2) = '3';
    *(c3+3) = 0;
    printf("c3 = %s\n", c3);

    // You cannot modify the value of `c4` (the address of the pointed memory location).
    // And, you cannot modify the content of the memory pointed by `c4`.
    printf("c4 = %s\n", c4);
}
```

Consequences:

```c
	const char* function( ... ) { ... }
```

In this case, the "`const`" is an indicator that the caller does not own the memory.
The caller must not modify the memory location referenced by the returned value (and, a fortiori, he must not call "`free()`" on the returned value).

```c
	void function(const char* in_c... ) { ... }
```

In this case, the "`const`" is an indicator that the _callee_ (in this case, the function) does not own the memory. The memory location referenced by the parameter "`in_c`" must not be modified within the function.

