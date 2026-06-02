#!/usr/bin/env python3
"""
Grading script for helm-charts-hardened skill test cases.
Evaluates assertions by checking for patterns in the generated chart files.
"""

import json
import os
import re
from pathlib import Path
from typing import Dict, List, Any

def check_file_contains(root_path: str, file_pattern: str, pattern: str) -> bool:
    """Check if a file matching the pattern contains the regex pattern."""
    search_path = Path(root_path)
    
    # Find files matching the pattern
    for file_path in search_path.rglob(file_pattern):
        if file_path.is_file():
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                    if re.search(pattern, content, re.IGNORECASE | re.MULTILINE):
                        return True
            except Exception:
                pass
    return False

def check_file_exists(root_path: str, file_pattern: str) -> bool:
    """Check if a file matching the pattern exists."""
    search_path = Path(root_path)
    for file_path in search_path.rglob(file_pattern):
        if file_path.is_file():
            return True
    return False

def check_files_exist_all(root_path: str, file_patterns: List[str]) -> bool:
    """Check if all files in the pattern list exist."""
    return all(check_file_exists(root_path, pattern) for pattern in file_patterns)

def grade_assertion(assertion: Dict, root_path: str) -> Dict[str, Any]:
    """Grade a single assertion."""
    assertion_id = assertion.get('id', 'unknown')
    text = assertion.get('text', '')
    
    try:
        # Determine the assertion type and check accordingly
        if assertion.get('type') == 'file_contains':
            file_pattern = assertion.get('file_pattern', '')
            pattern = assertion.get('pattern', '')
            passed = check_file_contains(root_path, file_pattern, pattern)
        elif assertion.get('type') == 'file_exists':
            file_pattern = assertion.get('file_pattern', '')
            passed = check_file_exists(root_path, file_pattern)
        elif assertion.get('type') == 'file_pattern':
            file_patterns = assertion.get('file_patterns', [])
            passed = check_files_exist_all(root_path, file_patterns)
        else:
            # Default: file_contains
            file_pattern = assertion.get('file_pattern', '')
            pattern = assertion.get('pattern', '')
            passed = check_file_contains(root_path, file_pattern, pattern)
        
        return {
            'text': text,
            'passed': passed,
            'evidence': f"Assertion {'passed' if passed else 'failed'}: {text}"
        }
    except Exception as e:
        return {
            'text': text,
            'passed': False,
            'evidence': f"Error during grading: {str(e)}"
        }

def grade_eval(eval_dir: str, eval_metadata: Dict) -> Dict[str, Any]:
    """Grade all assertions for an evaluation."""
    with_skill_path = os.path.join(eval_dir, 'with_skill', 'outputs')
    without_skill_path = os.path.join(eval_dir, 'without_skill', 'outputs')
    
    assertions = eval_metadata.get('assertions', [])
    
    with_skill_results = []
    without_skill_results = []
    
    for assertion in assertions:
        if os.path.exists(with_skill_path):
            with_skill_results.append(grade_assertion(assertion, with_skill_path))
        if os.path.exists(without_skill_path):
            without_skill_results.append(grade_assertion(assertion, without_skill_path))
    
    return {
        'with_skill': with_skill_results,
        'without_skill': without_skill_results
    }

def main():
    """Grade all test cases."""
    workspace_root = '/tmp/helm-charts-skill-workspace/iteration-1'
    
    # Process each eval
    for eval_id in range(1, 6):
        eval_dir = os.path.join(workspace_root, f'eval-{eval_id}')
        metadata_path = os.path.join(eval_dir, 'eval_metadata.json')
        
        if not os.path.exists(metadata_path):
            print(f"Warning: No metadata found for eval-{eval_id}")
            continue
        
        # Load metadata
        with open(metadata_path, 'r') as f:
            eval_metadata = json.load(f)
        
        # Grade the evaluation
        results = grade_eval(eval_dir, eval_metadata)
        
        # Save grading results
        with_skill_grading = os.path.join(eval_dir, 'with_skill', 'grading.json')
        without_skill_grading = os.path.join(eval_dir, 'without_skill', 'grading.json')
        
        os.makedirs(os.path.dirname(with_skill_grading), exist_ok=True)
        os.makedirs(os.path.dirname(without_skill_grading), exist_ok=True)
        
        with open(with_skill_grading, 'w') as f:
            json.dump({'expectations': results['with_skill']}, f, indent=2)
        
        with open(without_skill_grading, 'w') as f:
            json.dump({'expectations': results['without_skill']}, f, indent=2)
        
        # Print summary
        with_skill_pass = sum(1 for r in results['with_skill'] if r['passed'])
        without_skill_pass = sum(1 for r in results['without_skill'] if r['passed'])
        total = len(results['with_skill'])
        
        print(f"Eval {eval_id}: With Skill {with_skill_pass}/{total}, Without Skill {without_skill_pass}/{total}")

if __name__ == '__main__':
    main()
