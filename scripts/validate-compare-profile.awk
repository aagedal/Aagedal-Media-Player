# SPDX-License-Identifier: GPL-3.0-or-later
# Validate stdout metrics, not xcresult attachments (which duplicate stdout).
BEGIN {
    expected["COMPARE_PROFILE mpv/mpv"] = 1
    expected["COMPARE_PROFILE mpv/avFoundation"] = 1
    expected["COMPARE_PROFILE avFoundation/avFoundation"] = 1
    expected["COMPARE_PROFILE avFoundation/mpv"] = 1
    expected["COMPARE_PROFILE_VISUAL mpv/avFoundation"] = 1
    expected["COMPARE_PROFILE_VISUAL avFoundation/mpv"] = 1
    expected["COMPARE_PROFILE_SCOPE mpv/avFoundation"] = 1
    expected["COMPARE_PROFILE_SCOPE avFoundation/mpv"] = 1
}
function reject(message) {
    print "Compare Mode profile rejected: " message > "/dev/stderr"
    invalid = 1
}
# Accommodate XCTest's various skip formats, including xcodebuild summaries.
tolower($0) ~ /test skipped|test case .*skipped|[1-9][0-9]* tests? skipped|executed .*with [1-9][0-9]* tests? skipped/ {
    reject("test skipped")
}
/^COMPARE_PROFILE(_VISUAL|_SCOPE)? / {
    pair = $2
    if (pair !~ /^pair=[A-Za-z]+\/[A-Za-z]+,$/) {
        reject("malformed metric: " $0)
        next
    }
    sub(/^pair=/, "", pair)
    sub(/,$/, "", pair)
    key = $1 " " pair
    if (!(key in expected)) reject("unexpected scenario " key)
    if (++seen[key] > 1) reject("duplicate scenario " key)
}
END {
    for (key in expected) {
        if (!(key in seen)) reject("missing scenario " key)
    }
    exit invalid ? 1 : 0
}
