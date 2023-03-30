#!/usr/bin/perl
#
# Usage:
#
#     (1) with CLION, find the usage of the function and export the result to a file.
#     (2) edit the script configuration. Set the value for the constant `REPORT_PATH`.
#         Set the value of `REPORT_PATH` to the path to the CLION report file.
#     (3) execute the command below:
#
#         cd ${PROJECT ROOT}
#         perl tools/refactor.pl
#
# Note about "clang-format" configuration file (".clang-format")
# ==============================================================
#
#       ---
#       # We'll use defaults from the LLVM style, but with 4 columns indentation.
#       BasedOnStyle: LLVM
#       IndentWidth: 4
#       ---
#       Language: Cpp
#       ColumnLimit: 0
#       AlignConsecutiveAssignments: Consecutive
#
#       # Force pointers to the type for C++.
#       DerivePointerAlignment: false
#       PointerAlignment: Left
#
#       # Function calls.
#       AlignAfterOpenBracket: true  # If true, horizontally aligns arguments after an open bracket.
#       BinPackArguments: false
#       AllowAllArgumentsOnNextLine: false
#
#       # Functions declarations.
#       BinPackParameters: false # If false, a function declaration’s or function definition’s parameters will either all be on the same line or will have one line each.
#       AllowAllParametersOfDeclarationOnNextLine: true
#       ---
#
# Execution:
#
#       find ./src -name "*.c" -exec clang-format {} \;
#       find ./src -name "*.c" -exec clang-format {} \; | grep EFA_set_last_error_message
#
# Please note that it is not necessary to use "clang-format" in order to run this script.

use strict;
use warnings FATAL => 'all';
use Data::Dumper;

# ==============================================================================
#                             START OF CONFIGURATION
# ==============================================================================

use constant REPORT_PATH => 'tools/report.txt';

# ==============================================================================
#                               END OF CONFIGURATION
# ==============================================================================

use constant NOT_FOUND => 0;
use constant FOUND => 1;
use constant K_MARGIN => 'margin';
use constant K_TOKEN => 'token';
use constant K_LINE => 'line';
use constant K_POSITION => 'position';

# Load a source code from a file.
# @param $in_path Path to the file that contains the source code to load.
# @return An array of lines that represent the loaded source code.

sub load_code {
    my ($in_path) = @_;
    my $fd;
    my @lines;

    printf("L [%s]\n", $in_path);
    open($fd, '<', $in_path) or die(sprintf("Cannot open file \"%s\": $!", $in_path));
    @lines = <$fd>;
    close($fd);
    return @lines;
}

# Write a source code into a file.
# @param $in_path Path to the file that will be created.
# @param $in_code Text that represents the source code to write.

sub write_code {
    my ($in_path, $in_code) = @_;
    my $fd;

    printf("W [%s]\n", $in_path);
    open($fd, '>', $in_path) or die(sprintf("Cannot open file \"%s\": $!", $in_path));
    print $fd $in_code;
    close($fd);
}

# Find the call to a function identified by its name.
# @param $in_function_name The name of the function.
# @param $in_code The (C) code to scan for the function call.
# @return The function returns an array that contains 3 elements.
#         If a call to the function is found, then:
#           (1) the first element is the status flag: `&FOUND`.
#           (2) the second element represents the code that is before the call.
#           (3) the third element represents the code that is after the call.
#         Otherwise:
#           (1) the first element is the status flag: `&NOT_FOUND`.
#           (2) the second element is `undef`.
#           (3) the third element is `undef`.

sub find_function_call {
    my ($in_function_name, $in_code) = @_;

    if ($in_code =~ m/[^a-zA-Z0-9_](${in_function_name})\s*\(/g) {
        my $start = $-[1];
        my $stop = $+[1];
        my $before = substr($in_code, 0, $start);
        my $after = substr($in_code, $stop);

        return(&FOUND, $before, $after);
    }
    return(&NOT_FOUND, undef, undef);
}

# Parse the parameter list passed to a function call.
#
# Example:
#
#        Consider the following code:
#
#        int main() { function_call(1, 2); return 0; }
#
#        We are given the "code that follows the name of the function" (here, the function, FOR EXAMPLE, is
#        "function_call"). Thus the value of the parameter `$in_code` is:
#
#        $in_code = "(1, 2); return 0; }"
#
# @param $in_code The code that follows the name of the function.
#        Please note that this code should start with a "(".
# @return The function returns an array that contains 2 elements:
#            (1) the first element is a reference to an array that contains the parameters passed to the function.
#                example => ["1", "2"]
#            (2) the second element represents the code that follows the call.
#                example => "; return 0; }"
#            (3) the total number of lines that the call takes.
#                example => 1

sub split_function_call_params {
    my ($in_code) = @_;
    my $previous_char = undef;
    my $open_bracket = 0;
    my $open_string = 0;
    my $current_param_index = -1;
    my @params = ();
    my $after;
    my $position;
    my $line_count;

    $line_count = 0;
    for ($position=0; $position<length($in_code); $position++) {
        my $char = substr($in_code, $position, 1);
        $line_count += 1 if ("\n" eq $char);

        if (! defined($previous_char)) {
            # We look for the first "(". Skip whites.
            if ("(" ne $char) {
                if (! $char =~ m/\s/) {
                    die("Expecting a white, got \"${char}\" instead!");
                }
                next;
            }

            # We found the first "(". This is the start of the first parameter.
            $previous_char = $char; # it is "("
            $open_bracket += 1;
            $current_param_index += 1;
            push(@params, '');
            next;
        }

        # At this point, we are in the list of parameters. And we have a previous character.

        if ('\\' eq $previous_char) {
            # This is "\(", "\""... We should be in a string.
            if (0 == $open_bracket) {
                die("Unexpected \\ outside a string!");
            }

            $params[$current_param_index] .= $char;
            $previous_char = $char;
            next;
        }

        $previous_char = $char;

        # At this point, we have a previous character that is not '\'.

        if ('"' eq $char) {
            $open_string = $open_string ? 0 : 1;
            $params[$current_param_index] .= $char;
            next;
        }

        if (1 == $open_string) {
            $params[$current_param_index] .= $char;
            next;
        }

        # At this point, we have a previous character that is not '\', and we are not in a string.

        if ('(' eq $char) {
            $open_bracket += 1;
            $params[$current_param_index] .= $char;
            next;
        }

        if (')' eq $char) {
            $open_bracket -= 1;
            if (0 == $open_bracket) {
                last;
            }
            $params[$current_param_index] .= $char;
            next;
        }

        if (',' eq $char) {
            if ($open_bracket == 1) {
                # This is the start of a new parameter.
                $current_param_index += 1;
                push(@params, '');
                next;
            }
            # We are still in the current parameter.
            $params[$current_param_index] .= $char;
            next;
        }
        $params[$current_param_index] .= $char;
    }

    foreach my $param (@params) {
        $param =~ s/(^\s*|\s*$)//g;
    }

    # At this point, the character at the current position *IS* ")".
    $after = substr($in_code, $position+1);

    return(\@params, $after, $line_count);
}

# Compare 2 ID in the form "<path>:<line number>".
# @param $in_p1 First ID to compare.
# @param $in_p2 Second ID to compare.
# @return - if $in_p1 == $in_p2, return 0.
#         - if $in_p1 >  $in_p2, return +1.
#         - if $in_p1 <  $in_p2, return -1.

sub path_id_cmp {
    my ($in_p1, $in_p2) = @_;
    my ($p1, $l1) = split(':', $in_p1);
    my ($p2, $l2) = split(':', $in_p2);

    return -1 if ($p1 lt $p2);
    return +1 if ($p1 gt $p2);
    return($l1 <=> $l2);
}

# Parse the export generated by the CLION "Find usage" functionality.
# @param $in_path Path to the export file created by the CLION "Find usage" functionality.
# @return The function returns an array of "function locations". Each element of this array is a string in the form
#         "path:line".

sub export_parse {
    my ($in_path) = @_;
    my $fd = undef;
    my @document = ();
    my $position = 0;
    my @paths = ();

    open($fd, '<', $in_path) or die(sprintf("Cannot open file \"%s\": $!", $in_path));

    # Generate a simplified representation of the document to parse.
    # Keep only the lines which indentation is 8 or more.
    while(my $line = <$fd>) {
        my $len = undef;
        my $body = undef;
        my $line_number = undef;
        my $token = undef;

        $position += 1;

        # What is the value of the indentation?
        if ($line =~ m/^( *)([^ ].+)$/) {
            $len = length($1);
            $body = $2;
        }
        next if $len <= 8;

        # The line may represent:
        # - the (base)name of a directory (ex: "src  (145 usages found)")
        # - the (base)name of a file (ex: "efa_api.c  (67 usages found)")
        # - the name of a function (ex: EFA_create_directory  (4 usages found))
        # - a line of code (ex: 493 EFA_set_last_error_message(...))

        if ($body =~ m/^(\d+) .+$/) {
            # The line represents a line of code.
            $line_number = $1;
        } elsif ($body =~ m/^(.+)  \(\d+ usages? found\)\s*$/) {
            # The line represents:
            # - the (base)name of a directory, -OR-
            # - the (base)name of a file, -OR-
            # - the name of a function
            # [Q] Later, how will we know what does the line represent?
            # [R] By comparing margin values.
            $token = $1;
        } else {
            die(sprintf("Unexpected line \"%s\"", $line));
        }
        push(@document, { &K_MARGIN   => $len/4, # set for all
                          &K_TOKEN    => $token, # set for directories, files and function
                          &K_LINE     => $line_number, # set for lines of codes
                          &K_POSITION => $position }); # set for all
    }
    close($fd);

    # Generate the positions if the calls within the entire source.
    # We divide the "space" in 2 types of data:
    # (1) the lines of codes.
    # (2) the other data: directories (base)names, (source) files (base)names and functions names.
    my $last_start = 0;
    my $in_calls_section = 0; # TRUE or FALSE
    my $calls_section_margin = 0;
    my @current_path = ();
    for (my $i=0; $i<int(@document); $i++) {
        my $element = $document[$i];

        if (0 == $in_calls_section) {
            # We were within a series of path parts.
            if (defined($element->{&K_LINE})) {
                # We enter (for the first time) in a series of lines of code.
                $in_calls_section = 1;
                @current_path = ();
                $calls_section_margin = $element->{&K_MARGIN};
                # This section must be preceded by a "path section". build the path.
                for (my $j=$last_start; $j<$i-1; $j++) { push(@current_path, $document[$j]->{&K_TOKEN}); }
                push(@paths, sprintf("%s:%d", join('\\', @current_path), $element->{&K_LINE}));
                next;
            }
        }

        if (1 == $in_calls_section) {
            # We were within a series of lines of code.
            if (defined($element->{&K_LINE})) {
                # ... and we are still in the same series of lines of code.
                push(@paths, sprintf("%s:%d", join('\\', @current_path), $element->{&K_LINE}));
                next;
            }

            if (($calls_section_margin - 1) == $element->{&K_MARGIN}) {
                # This line presents the name of a function. Skip it.
                next;
            }

            if (($calls_section_margin - 2) == $element->{&K_MARGIN}) {
                # This line presents the name of a (source) file. Replace the last part of the current path.
                @current_path[$#current_path] = $element->{&K_TOKEN};
                next;
            }

            # We enter (for the first time) in a series of lines of path parts.
            $in_calls_section = 0;
            $last_start = $i;
            @current_path = ();
        }
    }

    # Sort the lines.
    @paths = sort {path_id_cmp($a, $b)} @paths;

    return(@paths);
}

# Extract the data from the CLION export and refactor the code.
#
# Please note:
#   (1) you must adapt this function to your needs. look for the section entitled "START REFACTORING HERE".
#   (2) the export from CLION gives the location (in the form of a line number in a file) of a function call.
#   (3) this algorithm is not 100% bulletproof, in the sense that the parsing of the C code is far from being perfect.
#       It does not work, in particular, and for example, if you have, in the code to parse, something that looks like:
#       /* function_call(1, 2, 3) */ function_call(1, 2); ...
#       The detection of the functions' name relies on regular expressions. If a function call appears in a comment,
#       then it will be treated as "normal, non-commented, code".
#
# @param $in_export_path Path to the CLION export.

sub refactor {
    my ($in_export_path) = @_;
    my @paths;
    my %files_data = ();

    # Parse the export file.
    @paths = export_parse($in_export_path);

    # For each function match, refactor the function call.
    my $c = 0;
    foreach my $path_line (@paths) {
        my ($path, $line_number) = split(':', $path_line);
        next if ($path =~ m/\.h$/);

        printf("\"%s:%d\" ", $path, $line_number);

        $files_data{$path} = 0 unless exists($files_data{$path}); # set the number of line to remove
        $line_number += $files_data{$path};

        printf("(-%d) -> %d\n", $files_data{$path}, $line_number);

        my @lines = load_code($path);
        if ($line_number > $#lines) { die(sprintf("%s: line overflow (%d)", $path, $line_number)) }

        my @before = @lines[0..$line_number-2];
        my @to_modify = @lines[$line_number-1..$#lines];
        my $code_before = join('', @before);
        my $code_to_modify = join('', @to_modify);

        # ==============================================================================
        #                          START OF FUNCTION CALL DETECTION
        # ==============================================================================

        # `find_function_call()`, return values:
        #   (1) a flag that tells whether the function call was found or not.
        #   (2) the text before the name of the function.
        #   (3) the text after the name of the function (that is: "(...)..."). This is the list of arguments, and the
        #       text that follows this list of arguments.
        my ($found, $call_before_function_name, $call_after_function_name) = find_function_call('last_error_set', $code_to_modify);
        if (&NOT_FOUND == $found) {
            # No call found. This is not normal!
            die(sprintf("A call should be found at %s:%d", $path, $line_number-1));
        }

        # `split_function_call_params()`, return values:
        #   (1) the first element is a reference to an array that contains the parameters passed to the function.
        #   (2) the second element represents the code that follows the call.
        #   (3) the total number of lines that the call takes.
        my ($params, $split_after, $line_count) = split_function_call_params($call_after_function_name);
        my @parameters = @{$params};

        # ==============================================================================
        #                          END OF FUNCTION CALL DETECTION
        # ==============================================================================

        # ==============================================================================
        #                           START REFACTORING HERE
        # ==============================================================================

        # Modify the function call.
        # In the C code, we have:
        #    last_error_set(TAG, __FILE__, __LINE__, __func__, "...",...);
        # In this current case:
        #    $parameters[0] = TAG
        #    $parameters[1] = __FILE__
        #    $parameters[2] = __LINE__
        #    $parameters[3] = __func__
        #    $parameters[4] = "..."
        #    ... and so on
        #
        #    `@parameters[4..$#parameters]` contains all parameters AFTER "`__func__`" (excluded).
        #
        # Below:
        #   (M1) we modify the call to the function call to refactor. We replace one or more lines by exactly one line.
        #        Indeed, the function call to replace may span over several lines. However, we replace this function
        #        call by a call that spans over a single line.
        #   (M2) we add a new line to the code (`printf(...)`).

        my $params_list = sprintf('(BASE_ERROR_ID + %d, __FILE__, __LINE__, __func__, ', $c++) . join(', ', @parameters[4..$#parameters]) . ')';
        my $printf_params_list = '(' . join(', ', @parameters[3..$#parameters]) . ')';
        my $new_code = $code_before . $call_before_function_name .
           'last_error_set' . $params_list . ";\n" . '/* TO-DELETE */ printf' . $printf_params_list .
           $split_after;

        $files_data{$path} -= $line_count; # for the modification of the function call (see M1)
        $files_data{$path} += 1; # for the added line (see M2)

        # ==============================================================================
        #                            STOP REFACTORING HERE
        # ==============================================================================

        write_code($path, $new_code);
    }
}

refactor(REPORT_PATH, undef);




# ==============================================================================
# Lines below this section are used for test only
# ==============================================================================

sub test_export_parse() {
    my $path = 'report.txt';
    my @paths = export_parse($path);
    print Dumper(\@paths);
}

sub test_find_function_call {
    my $code = 'char c;
               c = function_name (2 + 3); // this is a test
               printf("%c", c);';
    my ($found, $before, $after) = find_function_call('function_name', $code);
    if (&FOUND == $found) {
        print("FOUND\n");
        printf("before: [[%s]]\n", $before);
        printf("after:  [[%s]]\n", $after);
    } else {
        print("NOT FOUND\n");
    }

    $code = 'char c;
             c = function_name (2 + 3,
                                "toto",
                                "\"toto\""); // this is a test
             printf("%c", c);';
    ($found, $before, $after) = find_function_call('function_name', $code);
    if (&FOUND == $found) {
        print("FOUND\n");
        printf("before: [[%s]]\n", $before);
        printf("after:  [[%s]]\n", $after);
    } else {
        print("NOT FOUND\n");
    }
}

sub test_split_function_call_params() {
    my $code;
    my $after;
    my $params;
    my $lines_count;

    # ====================================================================

    $code = ' printf("\"a=%d, b=%s");
            // comment';
    printf("%s\n\n", "=" x 80);
    printf("%s\n\n", $code);
    printf("%s\n\n", "-" x 40);
    ($params, $after, $lines_count) = split_function_call_params($code);
    print Dumper($params);
    printf("after: => %s <= (%d lines)\n", $after, $lines_count);

    # ====================================================================

    $code = ' printf("a=%d, b=%s",
            10,
            "a string");
            // comment';
    printf("%s\n\n", "=" x 80);
    printf("%s\n\n", $code);
    printf("%s\n\n", "-" x 40);
    ($params, $after, $lines_count) = split_function_call_params($code);
    print Dumper($params);
    printf("after: => %s <= (%d lines)\n", $after, $lines_count);

    # ====================================================================

    $code = ' printf("a=%d, b=%s function(a, b)",
            10,
            "\"a string\"");';
    printf("%s\n\n", "=" x 80);
    printf("%s\n\n", $code);
    printf("%s\n\n", "-" x 40);
    ($params, $after, $lines_count) = split_function_call_params($code);
    print Dumper($params);
    printf("after: => %s <= (%d lines)\n", $after, $lines_count);

    # ====================================================================

    $code = ' printf("a=%d, b=%s function(a, b)",
            cos(120 + sin(2)),
            f1("abc", 10),
            "\"a string\"");';
    printf("%s\n\n", "=" x 80);
    printf("%s\n\n", $code);
    printf("%s\n\n", "-" x 40);
    ($params, $after, $lines_count) = split_function_call_params($code);
    print Dumper($params);
    printf("after: => %s <= (%d lines)\n", $after, $lines_count);

    # ====================================================================

    $code = ' printf("a=%d, b=%s function(a, b)",
            cos(120 + sin(2)),
            f1("abc", 10),
            "\"a string()")';
    printf("%s\n\n", "=" x 80);
    printf("%s\n\n", $code);
    printf("%s\n\n", "-" x 40);
    ($params, $after, $lines_count) = split_function_call_params($code);
    print Dumper($params);
    printf("after: => %s <= (%d lines)\n", $after, $lines_count);
}

# test_find_function_call();
# test_split_function_call_params();
# test_export_parse();

