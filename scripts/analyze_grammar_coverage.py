#!/usr/bin/env python3
"""
Script to analyze grammar coverage in property tests.

This script:
1. Parses elixir_parser.yrl and extracts grammar rules grouped by nonterminal
2. For each nonterminal, creates a prompt to review implementation coverage
3. Executes copilot agent to analyze each nonterminal
4. Writes results to a markdown file
"""

import re
import subprocess
import sys
import argparse
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Tuple


def strip_comments(line: str) -> str:
    """Remove Erlang-style comments (% to end of line) from a line."""
    # Be careful not to strip % inside strings
    # Simple approach: just find first % that's not in a string
    result = []
    in_string = False
    escape_next = False

    for i, char in enumerate(line):
        if escape_next:
            result.append(char)
            escape_next = False
            continue

        if char == '\\':
            result.append(char)
            escape_next = True
            continue

        if char == '"' or char == "'":
            in_string = not in_string
            result.append(char)
            continue

        if char == '%' and not in_string:
            # Comment starts here
            break

        result.append(char)

    return ''.join(result).rstrip()


def parse_yrl_file(yrl_path: Path) -> Dict[str, List[str]]:
    """
    Parse the .yrl file and extract grammar rules grouped by nonterminal.

    Returns a dict mapping nonterminal names to lists of complete rules.
    """
    content = yrl_path.read_text()

    # Split into lines for easier processing
    lines = content.split('\n')

    # Find where grammar rules start (after precedence declarations)
    # and where they end (before "Erlang code.")
    rule_start = None
    rule_end = None

    for i, line in enumerate(lines):
        # Look for the pattern of first grammar rule (typically "grammar ->")
        # Rules section starts after precedence declarations
        if rule_start is None and re.match(r'^[a-z_]+\s+->', line):
            rule_start = i
        # Erlang code section marker
        if line.strip() == 'Erlang code.':
            rule_end = i
            break

    if rule_start is None or rule_end is None:
        raise ValueError("Could not find grammar rules section")

    # Extract the rules section, stripping comments
    rules_lines = []
    for line in lines[rule_start:rule_end]:
        stripped = strip_comments(line)
        if stripped:  # Only add non-empty lines
            rules_lines.append(stripped)

    rules_section = '\n'.join(rules_lines)

    # Parse individual rules
    # Rules have format: nonterminal -> production : action.
    # Rules can span multiple lines and end with a period

    rules_by_nonterminal: Dict[str, List[str]] = defaultdict(list)

    # More robust approach: find all rules by looking for "nonterminal ->" patterns
    # and collecting until the next rule or end

    current_rule = []
    current_nonterminal = None

    for line in rules_section.split('\n'):
        # Check if this line starts a new rule
        match = re.match(r'^([a-z_]+)\s+->', line)
        if match:
            # Save previous rule if exists
            if current_rule and current_nonterminal:
                rule_text = '\n'.join(current_rule).strip()
                if rule_text:
                    rules_by_nonterminal[current_nonterminal].append(rule_text)

            # Start new rule
            current_nonterminal = match.group(1)
            current_rule = [line]
        else:
            # Continue current rule
            if current_rule:
                current_rule.append(line)

    # Don't forget the last rule
    if current_rule and current_nonterminal:
        rule_text = '\n'.join(current_rule).strip()
        if rule_text:
            rules_by_nonterminal[current_nonterminal].append(rule_text)

    # Clean up: merge multi-line rules and ensure each ends with a period
    cleaned_rules: Dict[str, List[str]] = {}
    for nonterminal, rules in rules_by_nonterminal.items():
        cleaned = []
        for rule in rules:
            # Normalize whitespace
            rule = re.sub(r'\s+', ' ', rule).strip()
            # Ensure ends with period
            if not rule.endswith('.'):
                rule += '.'
            cleaned.append(rule)
        cleaned_rules[nonterminal] = cleaned

    return cleaned_rules


def format_rules_block(nonterminal: str, rules: List[str]) -> str:
    """Format rules for a nonterminal into a readable block."""
    return '\n'.join(rules)


def create_prompt(nonterminal: str, rules: List[str]) -> str:
    """Create the analysis prompt for a nonterminal."""
    rules_text = format_rules_block(nonterminal, rules)

    prompt = f"""I'm implementing a property test that generates Elixir tokens from elixir grammar rules.

Your task is to review the implementation in the following files:
- test/spitfire/property/token_grammar_generators.exs
- test/spitfire/token_property_test.exs
- lib/spitfire/property/token_compiler.ex

Focus on the following grammar rules governing `{nonterminal}`:

```erlang
{rules_text}
```

Please analyze:
1. Are all cases for `{nonterminal}` implemented in the generators and compiler?
2. Are any cases marked as TODO for later phases?
3. Is the implementation correct according to the grammar rules?
4. Are there any edge cases or variations that might be missing?

Output a concrete list of actions needed to fill any gaps. If everything is implemented correctly, state that clearly."""

    return prompt


def run_agent(prompt: str, model: str, tool: str, cwd: Path) -> Tuple[str, int]:
    """
    Run agent with the given prompt.

    Args:
        prompt: The prompt to send
        model: Model name to use
        tool: Tool to use ('copilot' or 'claude')
        cwd: Working directory

    Returns (output, return_code)
    """
    if tool == 'claude':
        cmd = [
            'claude',
            '--model', model,
            '--allowedTools', 'Read,Glob,Grep',
            '-p', prompt
        ]
    else:  # copilot
        cmd = [
            'copilot',
            '--model', model,
            '--allow-all-tools',
            '-p', prompt
        ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=cwd,
            timeout=600  # 10 minute timeout per nonterminal
        )
        output = result.stdout
        if result.stderr:
            output += "\n\nSTDERR:\n" + result.stderr
        return output, result.returncode
    except subprocess.TimeoutExpired:
        return "ERROR: Command timed out after 10 minutes", 1
    except FileNotFoundError:
        return f"ERROR: {tool} command not found. Is it installed and in PATH?", 1
    except Exception as e:
        return f"ERROR: {str(e)}", 1


def write_results(results: Dict[str, Tuple[str, List[str]]], model: str, tool: str, output_path: Path):
    """Write results to markdown file."""
    from datetime import datetime

    # Calculate statistics
    total_nonterminals = len(results)
    total_rules = sum(len(rules) for _, (_, rules) in results.items())
    errors = sum(1 for _, (output, _) in results.items() if output.startswith('ERROR'))

    with output_path.open('w') as f:
        f.write(f"# Property Test Grammar Rule Coverage Analysis\n\n")
        f.write(f"## Summary\n\n")
        f.write(f"- **Model**: `{model}`\n")
        f.write(f"- **Tool**: `{tool}`\n")
        f.write(f"- **Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- **Nonterminals analyzed**: {total_nonterminals}\n")
        f.write(f"- **Total grammar rules**: {total_rules}\n")
        if errors:
            f.write(f"- **Errors**: {errors}\n")
        f.write("\n---\n\n")
        f.write("## Table of Contents\n\n")

        # Build TOC
        for nonterminal in results.keys():
            anchor = nonterminal.replace('_', '-')
            f.write(f"- [{nonterminal}](#{anchor})\n")
        f.write("\n---\n\n")

        for nonterminal, (output, rules) in results.items():
            f.write(f"## {nonterminal}\n\n")
            f.write(f"**Grammar Rules ({len(rules)}):**\n\n")
            f.write("```erlang\n")
            for rule in rules:
                f.write(f"{rule}\n")
            f.write("```\n\n")
            f.write("**Analysis:**\n\n")
            f.write(output)
            f.write("\n\n---\n\n")


def main():
    parser = argparse.ArgumentParser(
        description='Analyze grammar coverage in property tests'
    )
    parser.add_argument(
        '--model', '-m',
        default='claude-3-5-haiku-latest',
        help='Model to use for analysis (default: claude-3-5-haiku-latest)'
    )
    parser.add_argument(
        '--tool', '-t',
        choices=['copilot', 'claude'],
        default='claude',
        help='CLI tool to use (default: claude)'
    )
    parser.add_argument(
        '--limit', '-l',
        type=int,
        default=None,
        help='Limit number of nonterminals to analyze (for testing)'
    )
    parser.add_argument(
        '--nonterminals', '-n',
        nargs='+',
        default=None,
        help='Specific nonterminals to analyze (space-separated)'
    )
    parser.add_argument(
        '--dry-run', '-d',
        action='store_true',
        help='Print prompts without running agent'
    )
    parser.add_argument(
        '--list', '-L',
        action='store_true',
        help='List all nonterminals and exit'
    )
    parser.add_argument(
        '--output', '-o',
        type=Path,
        default=None,
        help='Output file path (default: PROP_TEST_RULE_COVERAGE_$MODEL.md)'
    )

    args = parser.parse_args()

    # Determine paths
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    yrl_path = project_root / 'elixir_parser.yrl'

    if not yrl_path.exists():
        print(f"ERROR: Grammar file not found at {yrl_path}")
        sys.exit(1)

    # Parse grammar
    print(f"Parsing grammar from {yrl_path}...")
    rules_by_nonterminal = parse_yrl_file(yrl_path)
    print(f"Found {len(rules_by_nonterminal)} nonterminals")

    # List mode
    if args.list:
        print("\nNonterminals:")
        for i, (name, rules) in enumerate(rules_by_nonterminal.items(), 1):
            print(f"  {i:3d}. {name} ({len(rules)} rules)")
        sys.exit(0)

    # Filter nonterminals if specified
    if args.nonterminals:
        filtered = {k: v for k, v in rules_by_nonterminal.items()
                   if k in args.nonterminals}
        if not filtered:
            print(f"ERROR: None of the specified nonterminals found: {args.nonterminals}")
            print(f"Available nonterminals: {list(rules_by_nonterminal.keys())}")
            sys.exit(1)
        rules_by_nonterminal = filtered

    # Apply limit if specified
    if args.limit:
        items = list(rules_by_nonterminal.items())[:args.limit]
        rules_by_nonterminal = dict(items)

    print(f"Analyzing {len(rules_by_nonterminal)} nonterminals using {args.tool}...")

    # Output file
    if args.output:
        output_path = args.output
    else:
        model_safe = args.model.replace('/', '_').replace(':', '_')
        output_path = project_root / f"PROP_TEST_RULE_COVERAGE_{model_safe}.md"

    results = {}

    for i, (nonterminal, rules) in enumerate(rules_by_nonterminal.items(), 1):
        print(f"\n[{i}/{len(rules_by_nonterminal)}] Analyzing: {nonterminal} ({len(rules)} rules)")

        prompt = create_prompt(nonterminal, rules)

        if args.dry_run:
            print(f"\n--- PROMPT for {nonterminal} ---")
            print(prompt)
            print("--- END PROMPT ---\n")
            output = f"[DRY RUN - prompt generated but not executed]\n\n```\n{prompt}\n```"
        else:
            print(f"  Running {args.tool} with model {args.model}...")
            output, returncode = run_agent(prompt, args.model, args.tool, project_root)

            if returncode != 0:
                print(f"  WARNING: {args.tool} returned non-zero exit code: {returncode}")

            print(f"  Done. Output length: {len(output)} chars")

        # Store both output and rules for better markdown formatting
        results[nonterminal] = (output, rules)

    # Write results
    print(f"\nWriting results to {output_path}...")
    write_results(results, args.model, args.tool, output_path)
    print("Done!")


if __name__ == '__main__':
    main()
