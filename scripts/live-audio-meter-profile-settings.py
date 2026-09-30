#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate the paced interval and budget the production XCTest deadline."""

import math
import sys


def execution_time_allowance(seconds, input_count):
    try:
        duration = float(seconds)
    except (TypeError, ValueError):
        raise ValueError("LIVE_AUDIO_METER_PROFILE_SECONDS must be a finite number from 5 through 1800") from None
    if not math.isfinite(duration) or not 5 <= duration <= 1_800:
        raise ValueError("LIVE_AUDIO_METER_PROFILE_SECONDS must be a finite number from 5 through 1800")
    if isinstance(input_count, bool) or not isinstance(input_count, int) or input_count < 1:
        raise ValueError("At least one profile input is required")
    # Each input loads twice (60 seconds each), checks pause/resume/cancellation
    # (15 seconds), then waits at most 36 seconds at EOF. Allow those existing
    # deadlines plus routing settlement and the complete paced observation.
    return math.ceil(120 + input_count * (180 + duration))


if __name__ == "__main__":
    try:
        print(execution_time_allowance(sys.argv[1], int(sys.argv[2])))
    except (IndexError, ValueError) as error:
        raise SystemExit(f"Invalid live audio meter profile settings: {error}") from error
