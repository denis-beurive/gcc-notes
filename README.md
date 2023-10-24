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

### `const <type> <var>`

```c
const char c
```

You cannot modify *value* of `c`. In other terms, `c` must be seen as is read-only variable.

```c
... function(const char c...) { ... }
```

In this case, the "`const`" is an indicator that the _callee_ (in this case, the function) cannot modify the value of `c`. In other terms, `c` must be seen as a read-only variable.

Illustration:

```bash
# The following tests fail.

$ echo "int main(){ const char c=0; c=1; }" | gcc -xc -
<stdin>: In function 'main':
<stdin>:1:30: error: assignment of read-only variable 'c'

$ echo "int main(){ const char c; c=1; }" | gcc -xc -
<stdin>: In function 'main':
<stdin>:1:28: error: assignment of read-only variable 'c'

$ echo "void nop(const char c){ c = 1; }; int main(){ char c=3; nop(c); }" | gcc -xc -
<stdin>: In function 'nop':
<stdin>:1:27: error: assignment of read-only parameter 'c'

# The following tests are OK

$ echo "void nop(const char c){}; int main(){ nop(3); }" | gcc -xc -

$ echo "void nop(const char c){}; int main(){ char c=3; nop(c); }" | gcc -xc -
```

### `const <type> *<var>`

```c
const char *c
```

You cannot modify the content of the memory location pointed by `c`.
However, you can modify the value of `c` (the address of the pointed memory location).

```c
... function(const char* c... ) { ... }
```

In this case, the "`const`" is an indicator that the _callee_ (in this case, the function) does not own the memory location. The memory location referenced by the parameter "`c`" must not be modified within the function. Thus, this prototype tells you that the function will *NOT* modify the content of the memory location which address is provided.

```c
const char* function( ... ) { ... }
```

In this case, the "`const`" is an *indicator* that the caller does not own the memory.
The caller must not modify the memory location referenced by the returned value (and, a fortiori, he must not call "`free()`" on the returned value). However, _by default_, the compiler may NOT stop the caller from acting wrongly.

```bash
# The following tests fail.

$ echo "int main(){ char value=1; const char *c=&value; *c=1; }" | gcc -xc -
<stdin>: In function 'main':
<stdin>:1:51: error: assignment of read-only location '*c'

$ echo "void nop(const char *c) { *c=1; }; int main(){ char value=1; nop(&value); }" | gcc -xc -
<stdin>: In function 'nop':
<stdin>:1:29: error: assignment of read-only location '*c'

$ echo "const char* f() { static char c=1; return &c; }; int main(){ char *c=f(); *c=1; }" | gcc -xc -Werror -
<stdin>: In function 'main':
<stdin>:1:70: error: initialization discards 'const' qualifier from pointer target type [-Werror=discarded-qualifiers]
cc1: all warnings being treated as errors

# The following tests do not fail, but are not correct.

$ echo "const char* f() { static char c=1; return &c; }; int main(){ char *c=f(); *c=1; }" | gcc -xc -
<stdin>: In function 'main':
<stdin>:1:70: warning: initialization discards 'const' qualifier from pointer target type [-Wdiscarded-qualifiers]

# The following tests are OK.

$ echo "int main(){ char value1=1; char value2=1; const char *c=&value1; c=&value2; }" | gcc -xc -

$ echo "void nop(const char *c) {}; int main(){ char value=1; nop(&value); }" | gcc -xc -

$ echo "void nop(const char *c) { char x=0; c=&x; }; int main(){ char value=1; nop(&value); }" | gcc -xc -

$ echo "const char* f() { static char c=1; return &c; }; int main(){ const char *c=f(); }" | gcc -xc -Werror -
```

### `<type>* const <var>`

```c
char* const c
```

You cannot modify the value of `c` (the address of the pointed memory location).
However, you can modify the content of the memory location pointed by `c`.

```c
... function(char* const c... ) { ... }
```

In this case, the "`const`" is an indicator that the _callee_ (in this case, the function) cannot modify the value of `c`. however, it can modify the content of the memory location pointed by `c`. Thus, this prototype tells you that the function will (_very likely_) modify the content of the memory location which address is provided.

Illustration:

```bash
# The following tests fail.

$ echo "int main(){ char value1=1; char value2=1; char* const c=&value1; c=&value2; }" | gcc -xc -
<stdin>: In function 'main':
<stdin>:1:67: error: assignment of read-only variable 'c'

$ echo "void nop(char* const c) { char x; c=&x; }; int main(){ char v=1; nop(&v); }" | gcc -xc -
<stdin>: In function 'nop':
<stdin>:1:36: error: assignment of read-only parameter 'c'

# The following tests are OK.

$ echo "int main(){ char value=1; char* const c=&value; *c=2; }" | gcc -xc -

$ echo "void nop(char* const c) { *c=10; }; int main(){ char v=1; nop(&v); }" | gcc -xc -
```

### `const <type>* const c4`

```c
const char* const c
```

You cannot modify the value of `c` (the address of the pointed memory location).
And, you cannot modify the content of the memory location pointed by `c`.

```c
... function(const char* const c... ) { ... }
```

In this case, the "`const`" is an indicator that the _callee_ (in this case, the function) cannot modify the value of `c` (the address of the pointed memory location), and cannot modify the content of the memory location which address is provided. Thus, this prototype tells you that the function will *NOT* modify the content of the memory location which address is provided.

Illustration:

```bash
# The following tests fail.

$ echo "int main(){ char value=1; const char* const c=&value; *c=2; }" | gcc -xc -
<stdin>: In function 'main':
<stdin>:1:57: error: assignment of read-only location '*(const char *)c'

$ echo "int main(){ char value1=1; char value2=1; const char* const c=&value1; c=&value2; }" | gcc -xc -
<stdin>: In function 'main':
<stdin>:1:73: error: assignment of read-only variable 'c'

$ echo "void nop(const char* const c) { *c=10; }; int main(){ char v=1; nop(&v); }" | gcc -xc -
<stdin>: In function 'nop':
<stdin>:1:35: error: assignment of read-only location '*(const char *)c'

$ echo "void nop(const char* const c) { char x=0; c=&x; }; int main(){ char v=1; nop(&v); }" | gcc -xc -
<stdin>: In function 'nop':
<stdin>:1:44: error: assignment of read-only parameter 'c'

# The following tests are OK.

echo "void nop(const char* const c) { char v=*c; const char *p=c; }; int main(){ char v=1; nop(&v); }" | gcc -xc -
```

## Retrieve data about a list of dynamic library

This script may be handdy:

```bash
#!/bin/bash

readonly FILES="
/usr/lib64/libpcsclite.so.1.0.0
/usr/lib64/libcrypto.so.3.0.7
"

function print_info {
  declare -r path="${1}"
  declare -r h=$(md5sum "${path}" | cut -d" " -f1)
  declare -r arch=$(export LANG=en_US.UTF-8; export LANGUAGE=en; objdump -f "${path}" | grep "file format" | cut -d: -f2 | sed "s/^[ \t]*//");

  printf "%s\n" "${path}"
  printf "  md5 \"%s\"\n" "${h}"
  printf "  %s\n" "${arch}"
}

while IFS= read -r file; do
  if [[ -n $file ]]; then
    print_info "${file}"
  fi
done <<< "${FILES}"
```

Output example:

```
/usr/lib64/libpcsclite.so.1.0.0
  md5 "7f208074768f643dca3888538b7c75ee"
  file format elf64-x86-64
/usr/lib64/libcrypto.so.3.0.7
  md5 "ee7151cec8e037bc26e84967965fc6c0"
  file format elf64-x86-64
```
