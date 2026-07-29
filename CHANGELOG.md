# Changelog

All notable changes to TwoPointWeather are documented here.

## 1.3.1 - 2026-07-29

- Applied TwoPoint Development branding throughout the repository.
- Added a complete GitHub repository structure and project documentation.
- Corrected the README version heading and installation guidance.
- Added community license, contribution guidance, security policy, issue forms, and pull request template.
- Preserved the 1.3.0 hard-sync runtime behavior without functional changes.

## 1.3.0 - 2026-07-28

- Added native-observed weather render verification.
- Added per-frame settled-weather and transition ownership.
- Added explicit rain and snow intensity synchronization.
- Added periodic full weather-state rebuilding.
- Added automatic client-side corrective resets.
- Added `/weather resync all` and `/weather resync [player ID]`.
- Expanded `/weather audit` with observed weather, transition progress, precipitation, corrections, and conflicting resources.

## 1.2.0 - 2026-07-21

- Added client/server timer calibration and latency compensation.
- Added exact transition progress for late joiners.
- Added exact state-revision acknowledgments.
- Added strict clock enforcement and diagnostic commands.
- Added resource-aware LB Phone integration events.

## 1.0.0

- Initial TwoPointWeather release.
- Added synchronized time, synchronized weather, dynamic weather, smooth admin transitions, ACE permissions, and LB Phone compatibility data.
