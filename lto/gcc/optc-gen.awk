#  Copyright (C) 2003, 2004, 2007, 2008, 2009 Free Software Foundation, Inc.
#  Contributed by Kelley Cook, June 2004.
#  Original code from Neil Booth, May 2003.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 3, or (at your option) any
# later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; see the file COPYING3.  If not see
# <http://www.gnu.org/licenses/>.

# This Awk script reads in the option records generated from 
# opt-gather.awk, combines the flags of duplicate options and generates a
# C file.
#
# This program uses functions from opt-functions.awk
#
# Usage: awk -f opt-functions.awk -f optc-gen.awk \
#            [-v header_name=header.h] < inputfile > options.c

BEGIN {
	n_opts = 0
	n_langs = 0
	n_target_save = 0
        quote = "\042"
	comma = ","
	FS=SUBSEP
	# Default the name of header created from opth-gen.awk to options.h
	if (header_name == "") header_name="options.h"
}

# Collect the text and flags of each option into an array
	{
		if ($1 == "Language") {
			langs[n_langs] = $2
			n_langs++;
		}
		else if ($1 == "TargetSave") {
			# Make sure the declarations are put in source order
			target_save_decl[n_target_save] = $2
			n_target_save++
		}
		else {
			name = opt_args("Mask", $1)
			if (name == "") {
				opts[n_opts]  = $1
				flags[n_opts] = $2
				help[n_opts]  = $3
				for (i = 4; i <= NF; i++)
					help[n_opts] = help[n_opts] " " $i
				n_opts++;
			}
		}
	}

# Dump that array of options into a C file.
END {
print "/* This file is auto-generated by optc-gen.awk.  */"
print ""
n_headers = split(header_name, headers, " ")
for (i = 1; i <= n_headers; i++)
	print "#include " quote headers[i] quote
print "#include " quote "opts.h" quote
print "#include " quote "intl.h" quote
print ""
print "#ifdef GCC_DRIVER"
print "int target_flags;"
print "#else"
print "#include " quote "flags.h" quote
print "#include " quote "target.h" quote
print "#endif /* GCC_DRIVER */"
print ""

have_save = 0;
for (i = 0; i < n_opts; i++) {
	if (flag_set_p("Save", flags[i]))
		have_save = 1;

	name = var_name(flags[i]);
	if (name == "")
		continue;

	if (flag_set_p("VarExists", flags[i])) {
		# Need it for the gcc driver.
		if (name in var_seen)
			continue;
		init = ""
		gcc_driver = 1
	}
	else {
		init = opt_args("Init", flags[i])
		if (init != "")
			init = " = " init;
		else if (name in var_seen)
			continue;
		gcc_driver = 0
	}

	if (gcc_driver == 1)
		print "#ifdef GCC_DRIVER"
	print "/* Set by -" opts[i] "."
	print "   " help[i] "  */"
	print var_type(flags[i]) name init ";"
	if (gcc_driver == 1)
		print "#endif /* GCC_DRIVER */"
	print ""

	var_seen[name] = 1;
}

print ""
print "/* Local state variables.  */"
for (i = 0; i < n_opts; i++) {
	name = static_var(opts[i], flags[i]);
	if (name != "")
		print "static " var_type(flags[i]) name ";"
}
print ""

print "const char * const lang_names[] =\n{"
for (i = 0; i < n_langs; i++) {
	macros[i] = "CL_" langs[i]
	gsub( "[^A-Za-z0-9_]", "X", macros[i] )
	s = substr("         ", length (macros[i]))
	print "  " quote langs[i] quote ","
    }

print "  0\n};\n"
print "const unsigned int cl_options_count = N_OPTS;\n"
print "const unsigned int cl_lang_count = " n_langs ";\n"

print "const struct cl_option cl_options[] =\n{"

j = 0
for (i = 0; i < n_opts; i++) {
	back_chain[i] = "N_OPTS";
	indices[opts[i]] = j;
	# Combine the flags of identical switches.  Switches
	# appear many times if they are handled by many front
	# ends, for example.
	while( i + 1 != n_opts && opts[i] == opts[i + 1] ) {
		flags[i + 1] = flags[i] " " flags[i + 1];
		if (help[i + 1] == "")
			help[i + 1] = help[i]
		else if (help[i] != "" && help[i + 1] != help[i])
			print "warning: multiple different help strings for " \
				opts[i] ":\n\t" help[i] "\n\t" help[i + 1] \
				| "cat 1>&2"
		i++;
		back_chain[i] = "N_OPTS";
		indices[opts[i]] = j;
	}
	j++;
}

for (i = 0; i < n_opts; i++) {
	# With identical flags, pick only the last one.  The
	# earlier loop ensured that it has all flags merged,
	# and a nonempty help text if one of the texts was nonempty.
	while( i + 1 != n_opts && opts[i] == opts[i + 1] ) {
		i++;
	}

	len = length (opts[i]);
	enum = "OPT_" opts[i]
	if (opts[i] == "finline-limit=" || opts[i] == "Wlarger-than=")
		enum = enum "eq"
	gsub ("[^A-Za-z0-9]", "_", enum)

	# If this switch takes joined arguments, back-chain all
	# subsequent switches to it for which it is a prefix.  If
	# a later switch S is a longer prefix of a switch T, T
	# will be back-chained to S in a later iteration of this
	# for() loop, which is what we want.
	if (flag_set_p("Joined.*", flags[i])) {
		for (j = i + 1; j < n_opts; j++) {
			if (substr (opts[j], 1, len) != opts[i])
				break;
			back_chain[j] = enum;
		}
	}

	s = substr("                                  ", length (opts[i]))
	if (i + 1 == n_opts)
		comma = ""

	if (help[i] == "")
		hlp = "0"
	else
		hlp = quote help[i] quote;

	neg = opt_args("Negative", flags[i]);
	if (neg != "")
		idx = indices[neg]
	else {
		if (flag_set_p("RejectNegative", flags[i]))
			idx = -1;
		else {
			if (opts[i] ~ "^[Wfm]")
				idx = indices[opts[i]];
			else
				idx = -1;
		}
	}
	# Split the printf after %u to work around an ia64-hp-hpux11.23
	# awk bug.
	printf("  { %c-%s%c,\n    %s,\n    %s, %u,",
	       quote, opts[i], quote, hlp, back_chain[i], len)
	printf(" %d,\n", idx)
	condition = opt_args("Condition", flags[i])
	cl_flags = switch_flags(flags[i])
	if (condition != "")
		printf("#if %s\n" \
		       "    %s,\n" \
		       "#else\n" \
		       "    CL_DISABLED,\n" \
		       "#endif\n",
		       condition, cl_flags, cl_flags)
	else
		printf("    %s,\n", cl_flags)
	printf("    %s, %s }%s\n", var_ref(opts[i], flags[i]),
	       var_set(flags[i]), comma)
}

print "};"

print "";
print "#if !defined(GCC_DRIVER) && !defined(IN_LIBGCC2) && !defined(IN_TARGET_LIBS)"
print "";
print "/* Save optimization variables into a structure.  */"
print "void";
print "cl_optimization_save (struct cl_optimization *ptr)";
print "{";

n_opt_char = 2;
n_opt_short = 0;
n_opt_int = 0;
n_opt_other = 0;
var_opt_char[0] = "optimize";
var_opt_char[1] = "optimize_size";
var_opt_range["optimize"] = "0, 255";
var_opt_range["optimize_size"] = "0, 255";

# Sort by size to mimic how the structure is laid out to be friendlier to the
# cache.

for (i = 0; i < n_opts; i++) {
	if (flag_set_p("Optimization", flags[i])) {
		name = var_name(flags[i])
		if(name == "")
			continue;

		if(name in var_opt_seen)
			continue;

		var_opt_seen[name]++;
		otype = var_type_struct(flags[i]);
		if (otype ~ "^((un)?signed +)?int *$")
			var_opt_int[n_opt_int++] = name;

		else if (otype ~ "^((un)?signed +)?short *$")
			var_opt_short[n_opt_short++] = name;

		else if (otype ~ "^((un)?signed +)?char *$") {
			var_opt_char[n_opt_char++] = name;
			if (otype ~ "^unsigned +char *$")
				var_opt_range[name] = "0, 255"
			else if (otype ~ "^signed +char *$")
				var_opt_range[name] = "-128, 127"
		}
		else
			var_opt_other[n_opt_other++] = name;
	}
}

for (i = 0; i < n_opt_char; i++) {
	name = var_opt_char[i];
	if (var_opt_range[name] != "")
		print "  gcc_assert (IN_RANGE (" name ", " var_opt_range[name] "));";
}

print "";
for (i = 0; i < n_opt_other; i++) {
	print "  ptr->" var_opt_other[i] " = " var_opt_other[i] ";";
}

for (i = 0; i < n_opt_int; i++) {
	print "  ptr->" var_opt_int[i] " = " var_opt_int[i] ";";
}

for (i = 0; i < n_opt_short; i++) {
	print "  ptr->" var_opt_short[i] " = " var_opt_short[i] ";";
}

for (i = 0; i < n_opt_char; i++) {
	print "  ptr->" var_opt_char[i] " = " var_opt_char[i] ";";
}

print "}";

print "";
print "/* Restore optimization options from a structure.  */";
print "void";
print "cl_optimization_restore (struct cl_optimization *ptr)";
print "{";

for (i = 0; i < n_opt_other; i++) {
	print "  " var_opt_other[i] " = ptr->" var_opt_other[i] ";";
}

for (i = 0; i < n_opt_int; i++) {
	print "  " var_opt_int[i] " = ptr->" var_opt_int[i] ";";
}

for (i = 0; i < n_opt_short; i++) {
	print "  " var_opt_short[i] " = ptr->" var_opt_short[i] ";";
}

for (i = 0; i < n_opt_char; i++) {
	print "  " var_opt_char[i] " = ptr->" var_opt_char[i] ";";
}

print "}";

print "";
print "/* Print optimization options from a structure.  */";
print "void";
print "cl_optimization_print (FILE *file,";
print "                       int indent_to,";
print "                       struct cl_optimization *ptr)";
print "{";

print "  fputs (\"\\n\", file);";
for (i = 0; i < n_opt_other; i++) {
	print "  if (ptr->" var_opt_other[i] ")";
	print "    fprintf (file, \"%*s%s (0x%lx)\\n\",";
	print "             indent_to, \"\",";
	print "             \"" var_opt_other[i] "\",";
	print "             (unsigned long)ptr->" var_opt_other[i] ");";
	print "";
}

for (i = 0; i < n_opt_int; i++) {
	print "  if (ptr->" var_opt_int[i] ")";
	print "    fprintf (file, \"%*s%s (0x%x)\\n\",";
	print "             indent_to, \"\",";
	print "             \"" var_opt_int[i] "\",";
	print "             ptr->" var_opt_int[i] ");";
	print "";
}

for (i = 0; i < n_opt_short; i++) {
	print "  if (ptr->" var_opt_short[i] ")";
	print "    fprintf (file, \"%*s%s (0x%x)\\n\",";
	print "             indent_to, \"\",";
	print "             \"" var_opt_short[i] "\",";
	print "             ptr->" var_opt_short[i] ");";
	print "";
}

for (i = 0; i < n_opt_char; i++) {
	print "  if (ptr->" var_opt_char[i] ")";
	print "    fprintf (file, \"%*s%s (0x%x)\\n\",";
	print "             indent_to, \"\",";
	print "             \"" var_opt_char[i] "\",";
	print "             ptr->" var_opt_char[i] ");";
	print "";
}

print "}";

print "";
print "/* Save selected option variables into a structure.  */"
print "void";
print "cl_target_option_save (struct cl_target_option *ptr)";
print "{";

n_target_char = 0;
n_target_short = 0;
n_target_int = 0;
n_target_other = 0;

if (have_save) {
	for (i = 0; i < n_opts; i++) {
		if (flag_set_p("Save", flags[i])) {
			name = var_name(flags[i])
			if(name == "")
				name = "target_flags";

			if(name in var_save_seen)
				continue;

			var_save_seen[name]++;
			otype = var_type_struct(flags[i])
			if (otype ~ "^((un)?signed +)?int *$")
				var_target_int[n_target_int++] = name;

			else if (otype ~ "^((un)?signed +)?short *$")
				var_target_short[n_target_short++] = name;

			else if (otype ~ "^((un)?signed +)?char *$") {
				var_target_char[n_target_char++] = name;
				if (otype ~ "^unsigned +char *$")
					var_target_range[name] = "0, 255"
				else if (otype ~ "^signed +char *$")
					var_target_range[name] = "-128, 127"
			}
			else
				var_target_other[n_target_other++] = name;
		}
	}
} else {
	var_target_int[n_target_int++] = "target_flags";
}

have_assert = 0;
for (i = 0; i < n_target_char; i++) {
	name = var_target_char[i];
	if (var_target_range[name] != "") {
		have_assert = 1;
		print "  gcc_assert (IN_RANGE (" name ", " var_target_range[name] "));";
	}
}

if (have_assert)
	print "";

print "  if (targetm.target_option.save)";
print "    targetm.target_option.save (ptr);";
print "";

for (i = 0; i < n_target_other; i++) {
	print "  ptr->" var_target_other[i] " = " var_target_other[i] ";";
}

for (i = 0; i < n_target_int; i++) {
	print "  ptr->" var_target_int[i] " = " var_target_int[i] ";";
}

for (i = 0; i < n_target_short; i++) {
	print "  ptr->" var_target_short[i] " = " var_target_short[i] ";";
}

for (i = 0; i < n_target_char; i++) {
	print "  ptr->" var_target_char[i] " = " var_target_char[i] ";";
}

print "}";

print "";
print "/* Restore selected current options from a structure.  */";
print "void";
print "cl_target_option_restore (struct cl_target_option *ptr)";
print "{";

for (i = 0; i < n_target_other; i++) {
	print "  " var_target_other[i] " = ptr->" var_target_other[i] ";";
}

for (i = 0; i < n_target_int; i++) {
	print "  " var_target_int[i] " = ptr->" var_target_int[i] ";";
}

for (i = 0; i < n_target_short; i++) {
	print "  " var_target_short[i] " = ptr->" var_target_short[i] ";";
}

for (i = 0; i < n_target_char; i++) {
	print "  " var_target_char[i] " = ptr->" var_target_char[i] ";";
}

# This must occur after the normal variables in case the code depends on those
# variables.
print "";
print "  if (targetm.target_option.restore)";
print "    targetm.target_option.restore (ptr);";

print "}";

print "";
print "/* Print optimization options from a structure.  */";
print "void";
print "cl_target_option_print (FILE *file,";
print "                        int indent,";
print "                        struct cl_target_option *ptr)";
print "{";

print "  fputs (\"\\n\", file);";
for (i = 0; i < n_target_other; i++) {
	print "  if (ptr->" var_target_other[i] ")";
	print "    fprintf (file, \"%*s%s (0x%lx)\\n\",";
	print "             indent, \"\",";
	print "             \"" var_target_other[i] "\",";
	print "             (unsigned long)ptr->" var_target_other[i] ");";
	print "";
}

for (i = 0; i < n_target_int; i++) {
	print "  if (ptr->" var_target_int[i] ")";
	print "    fprintf (file, \"%*s%s (0x%x)\\n\",";
	print "             indent, \"\",";
	print "             \"" var_target_int[i] "\",";
	print "             ptr->" var_target_int[i] ");";
	print "";
}

for (i = 0; i < n_target_short; i++) {
	print "  if (ptr->" var_target_short[i] ")";
	print "    fprintf (file, \"%*s%s (0x%x)\\n\",";
	print "             indent, \"\",";
	print "             \"" var_target_short[i] "\",";
	print "             ptr->" var_target_short[i] ");";
	print "";
}

for (i = 0; i < n_target_char; i++) {
	print "  if (ptr->" var_target_char[i] ")";
	print "    fprintf (file, \"%*s%s (0x%x)\\n\",";
	print "             indent, \"\",";
	print "             \"" var_target_char[i] "\",";
	print "             ptr->" var_target_char[i] ");";
	print "";
}

print "";
print "  if (targetm.target_option.print)";
print "    targetm.target_option.print (file, indent, ptr);";

print "}";
print "#endif";

}