# Spitfire - CLAUDE Development Guide

## Project Overview

Spitfire is an error-resilient Elixir parser built using a Pratt parser architecture. It's designed to provide better code intelligence for editor tooling by parsing incomplete or malformed Elixir code gracefully.

**Key Features:**
- Error-tolerant parsing of Elixir syntax
- Core-compatible AST output
- Environment querying API for editor tooling
- Handwritten Pratt parser for better error recovery

## Architecture

### Parser Design
- **Type**: Pratt parser (top-down operator precedence)
- **Main module**: `lib/spitfire.ex` (~2.8K LOC)
- **Tokenizer**: `src/spitfire_tokenizer.erl` (Erlang)
- **Interpolation**: `src/spitfire_interpolation.erl` (Erlang)

### Key Components
- **Null denotation (nud)**: Handles prefix/atomic expressions
- **Left denotation (led)**: Handles infix/postfix expressions
- **Precedence table**: `@precedences` map with binding powers
- **Error recovery**: Synthetic token injection and terminator sets
- **Fuel system**: Prevents infinite recursion (150 step limit)

## Development Setup

### Dependencies
```elixir
# Development only
{:ex_doc, ">= 0.0.0", only: :dev}
{:styler, "~> 0.11", only: :dev}
{:credo, "~> 1.7", only: :dev}
{:dialyxir, "~> 1.0", only: :dev}
{:toxic, path: "/Users/lukaszsamson/claude_fun/toxic"}
```

### Commands
- `mix test` - Run test suite
- `mix docs` - Generate documentation
- `mix credo` - Code analysis
- `mix dialyzer` - Type checking

### Project Structure
```
lib/
├── spitfire.ex          # Main parser module
├── spitfire/
    ├── env.ex           # Environment querying
    ├── tracer.ex        # Debug tracing
    └── while.ex         # Parser utilities

src/
├── spitfire_tokenizer.erl      # Tokenizer (Erlang)
└── spitfire_interpolation.erl  # String interpolation (Erlang)

test/
├── spitfire_test.exs    # Main parser tests
└── spitfire/
    └── env_test.exs     # Environment tests
```

## Parser Implementation Details

### Precedence Levels (highest to lowest)
- `@at_op` (64): Module attributes `@`
- `@dot_call_op` (60): Function calls `.`
- `@power_op` (52): Exponentiation `**`
- `@pipe_op` (22): Pipe operator `|>`
- `@doo` (4): `do` keyword

### Error Handling
- Errors accumulate in `parser.errors` without stopping parsing
- Synthetic tokens injected for missing closers
- Fuel system prevents infinite loops
- Two-token lookahead for precedence decisions

### Adding New Operators
1. Add token type to tokenizer
2. Insert precedence entry in `@precedences`
3. Extend parser case clauses in `parse_expression/6`

## Testing

Run the test suite with:
```bash
mix test
```

Tests cover:
- Core parsing functionality
- Error recovery scenarios
- Environment querying API
- Edge cases and malformed input

## Current Development

The parser is feature-complete for Elixir syntax. Current focus areas:
- Improving error resilience
- Optimizing parsing speed
- Enhancing environment querying capabilities

## Contributing Guidelines

- Follow existing code style and patterns
- Add tests for new functionality
- Update documentation for API changes
- Consider error recovery implications for new features
- Use `mix credo` and `mix dialyzer` for code quality

## Acknowledgments

Built by Mitchell Hanberg, inspired by Thorsten Ball's "Writing an Interpreter in Go" and modern error-tolerant parsers like rustc and Ruby's Prism.