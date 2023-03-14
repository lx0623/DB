// $Id$ 	
/** \file driver.h Declaration of the example::Driver class. */

#ifndef EXAMPLE_DRIVER_H
#define EXAMPLE_DRIVER_H

#include <string>
#include <vector>

#include "frontend/AriesSQLStatement.h"
#include "common.h"
#include "parser.hh"


using namespace aries;

namespace aries_parser {

/** The Driver class brings together all components. It creates an instance of
 * the Parser and Scanner classes and connects them. Then the input stream is
 * fed into the scanner object and the parser gets it's token
 * sequence. Furthermore the driver object is available in the grammar rules as
 * a parameter. Therefore the driver class contains a reference to the
 * structure into which the parsed data is saved. */
class Driver
{
public:
    /// construct a new parser driver context
    Driver();

    /// enable debug output in the flex scanner
    bool trace_scanning;

    /// enable debug output in the bison parser
    bool trace_parsing;

    /// stream name (file or input stream) used for error messages.
    std::string streamname;

    char* input_buf = nullptr;

    /** Invoke the scanner and parser for a stream.
     * @param in	input stream
     * @param sname	stream name for error messages
     * @return		true if successfully parsed
     */
    bool parse_stream(std::istream &in,
                      const std::string &sname = "stream input");

    bool parse_stdin();

    /** Invoke the scanner and parser on an input string.
     * @param input	input string
     * @param sname	stream name for error messages
     * @return		true if successfully parsed
     */
    bool parse_string(const std::string& input);

    /** Invoke the scanner and parser on a file. Use parse_stream with a
     * std::ifstream if detection of file reading errors is required.
     * @param filename	input file name
     * @return		true if successfully parsed
     */
    bool parse_file(const std::string& filename);

    // To demonstrate pure handling of parse errors, instead of
    // simply dumping them on the standard error output, we will pass
    // them to the driver using the following two member functions.

    /** Error handling with associated line number. This can be modified to
     * output the error e.g. to a dialog box. */
    void error(const class location& l, const std::string& m);

    /** General error handling. This can be modified to output the error
     * e.g. to a dialog box. */
    void error(const std::string& m);

    /** Pointer to the current lexer instance, this is used to connect the
     * parser to the scanner. It is used in the yylex macro. */
    class Scanner* lexer;

    std::vector<AriesSQLStatementPointer> statements;

    std::string get_string_at_location(location l);

    std::vector<BiaodashiPointer> global_expr_list;
    VALUES_LIST global_insert_values_list;

private:
    bool parse_stream_internal(std::istream &in, long length);
};

} // namespace aries_parser

#endif // EXAMPLE_DRIVER_H
