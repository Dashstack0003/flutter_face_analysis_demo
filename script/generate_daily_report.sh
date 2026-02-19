#!/bin/bash

# ===============================
# CONFIGURATION
# ===============================

DEV_NAME=$(git config user.name)
DATE=$(date +"%Y-%m-%d")
TIME=$(date +"%H:%M:%S")

BASE_DIR="reports/$DEV_NAME"
SUMMARY_FILE="$BASE_DIR/${DATE}_daily_summary.txt"
QUALITY_FILE="$BASE_DIR/${DATE}_code_quality.txt"

mkdir -p "$BASE_DIR"

echo "Generating report for $DEV_NAME on $DATE..."

# ===============================
# GET TODAY COMMITS
# ===============================

COMMITS=$(git log --since="today 00:00" --pretty=format:"%s")

if [ -z "$COMMITS" ]; then
    echo "No commits found for today."
    exit 0
fi

# ===============================
# CATEGORIZE COMMITS
# ===============================

FEATURES=$(echo "$COMMITS" | grep "^feat:")
FIXES=$(echo "$COMMITS" | grep "^fix:")
REFACTORS=$(echo "$COMMITS" | grep "^refactor:")
TESTS=$(echo "$COMMITS" | grep "^test:")
DOCS=$(echo "$COMMITS" | grep "^docs:")
CHORES=$(echo "$COMMITS" | grep "^chore:")

TOTAL_COMMITS=$(echo "$COMMITS" | wc -l)

FILES_CHANGED=$(git log --since="today 00:00" --name-only --pretty=format: | sort | uniq | wc -l)

# ===============================
# ASK FOR MANUAL TASKS
# ===============================

echo ""
echo "Enter additional tasks completed today (press ENTER to skip):"
read MANUAL_TASK

# ===============================
# GENERATE SUMMARY FILE
# ===============================

{
echo "========================================="
echo "           DAILY WORK SUMMARY"
echo "========================================="
echo "Developer: $DEV_NAME"
echo "Date: $DATE"
echo "Time Generated: $TIME"
echo ""

echo "🆕 Features Completed:"
echo "$FEATURES"
echo ""

echo "🐛 Bugs Fixed:"
echo "$FIXES"
echo ""

echo "♻️ Refactoring:"
echo "$REFACTORS"
echo ""

echo "🧪 Tests Added:"
echo "$TESTS"
echo ""

echo "📚 Documentation:"
echo "$DOCS"
echo ""

echo "⚙️ Chores:"
echo "$CHORES"
echo ""

if [ ! -z "$MANUAL_TASK" ]; then
echo "📝 Additional Work (Non-Commit Tasks):"
echo "- $MANUAL_TASK"
echo ""
fi

echo "-----------------------------------------"
echo "Total Commits: $TOTAL_COMMITS"
echo "Files Changed: $FILES_CHANGED"
echo "-----------------------------------------"

} > "$SUMMARY_FILE"

# ===============================
# RUN FLUTTER ANALYSIS
# ===============================

echo "Running Flutter analyzer..."

flutter analyze > analysis_output.txt 2>&1

ERRORS=$(grep -c "error •" analysis_output.txt)
WARNINGS=$(grep -c "warning •" analysis_output.txt)
INFO=$(grep -c "info •" analysis_output.txt)

TOP_WARNINGS=$(grep "warning •" analysis_output.txt | awk -F '•' '{print $2}' | sort | uniq -c | sort -nr | head -5)

# ===============================
# GENERATE CODE QUALITY FILE
# ===============================

{
echo "========================================="
echo "          CODE QUALITY REPORT"
echo "========================================="
echo "Developer: $DEV_NAME"
echo "Date: $DATE"
echo "Time Generated: $TIME"
echo ""

echo "❌ Errors: $ERRORS"
echo "⚠️ Warnings: $WARNINGS"
echo "ℹ️ Info: $INFO"
echo ""

echo "Top Warning Types:"
echo "$TOP_WARNINGS"
echo ""

echo "Recommendation:"
echo "- Resolve all errors immediately."
echo "- Reduce repeated warning patterns."
echo "- Review large widgets and long methods."
echo "- Remove unused imports and debug prints."

} > "$QUALITY_FILE"

rm analysis_output.txt

echo ""
echo "✅ Reports generated successfully!"
echo "📄 $SUMMARY_FILE"
echo "📄 $QUALITY_FILE"