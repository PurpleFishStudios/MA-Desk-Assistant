# MA Desk Assistant — fictional-case tester script

Version/build: __________  Date: __________  Tester ID (optional): __________
Observer: __________  macOS version (optional): __________

## Before starting

Use invented cases only. Do not enter real patient names, birth dates, identifiers, medical records, screenshots containing patient information, or real clinical notes. The app is a practice prototype, not a patient chart, diagnostic tool, or billing tool. Tell the tester: “Please narrate what you expect to happen. I’ll observe rather than guide you.”

## Fictional scenario

Case ID: DEMO-RASH-001. An invented adult reports an itchy rash on the forearm for three days. For the exercise only: HPI says the rash appeared after trying a new soap; ROS states no fever; PE states a small red patch on the forearm. Leave Assessment and Plan blank initially. These facts are invented and are not instructions to diagnose or treat.

## Tasks (observe without prompting)

1. Find Practice Cases and create a new case. Enter the fictional ID and title “Soap-change rash practice.” Record where the tester hesitates.
2. Enter the supplied Reason for Visit, HPI, ROS, and PE. Save the draft, switch cases, return, and check that the text remains.
3. Open Draft review. Ask the tester to identify which sections are marked “Not entered” and whether they understand that the checklist checks presence of text, not correctness.
4. Open the ICD-10-CM reference lookup. Ask the tester to search a fictional-case term and inspect a result’s description, specificity badge, and instructional notes. Do not ask them to select a final diagnosis; if they attach a code, it is only a reference for review.
5. Preview the note and export a PDF. Ask the tester to find the fictional-case disclaimer, missing-section labels, and any manually attached reference. Have them open the PDF and check readability.
6. Change one note field without saving, then press Export PDF. Ask what they expect the PDF to contain; verify the last-saved-version warning, then cancel. Do not save an unintended file.

## Feedback checklist

For each task, record: Completed without help / Completed with help / Could not complete; time or hesitation; exact confusing wording; expected result; actual result. Record observations, not diagnoses or patient data.

| Task | Outcome | Where they hesitated / exact quote | Expected vs actual |
|---|---|---|---|
| Create case | | | |
| Save and reopen draft | | | |
| Find missing sections | | | |
| Review ICD-10-CM result | | | |
| Preview and export PDF | | | |
| Unsaved-edit export warning | | | |

## Short interview

- What felt easiest?
- What felt confusing or took too many steps?
- Did “reference for review” versus “assigned diagnosis” make sense?
- Was it clear when text was saved and which version the PDF contained?
- What single change would help you most? Avoid collecting real patient examples.

## Triage after the session

Log each issue separately with build number, reproducible steps, expected result, actual result, severity (Blocker / High / Medium / Low), and whether a fictional-data-only screenshot exists. Prioritize lost data, export omissions or clipping, misleading clinical labels, and crashes before polish or new features. Keep feedback private and omit identifying medical details.
