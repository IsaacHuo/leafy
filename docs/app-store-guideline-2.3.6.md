# App Store Guideline 2.3.6 Metadata Correction

Use this checklist for the Guideline 2.3.6 rejection about inaccurate Age Rating metadata.

## App Store Connect Changes

- Go to `Apps -> Leafy -> General -> App Information -> Age Ratings -> Edit`.
- In `In-App Controls`, set `Parental Controls` to `None`.
- In `In-App Controls`, set `Age Assurance` to `None`.
- Keep truthful content descriptors for anonymous UGC, messaging/community interactions, and any other actual content.
- If the calculated rating is lower than 18+, use `Override to Higher Age Rating` and select 18+ to reflect the app's anonymous UGC and community moderation requirements.
- Save the Age Ratings changes before replying or resubmitting.

## Review Notes

We corrected the Age Rating metadata in App Store Connect. Leafy does not include Apple-defined Parental Controls or Age Assurance mechanisms, so both selections are now set to `None`.

The app's higher age rating is retained to accurately reflect anonymous user-generated community features and moderation requirements. This higher rating is not based on Parental Controls or Age Assurance.

## Reviewer Reply Draft

Hello,

Thank you for the clarification. The app does not include Parental Controls or Age Assurance mechanisms. We have updated the Age Rating selections in App Store Connect so that both "Parental Controls" and "Age Assurance" are set to "None."

The app's higher age rating is retained to accurately reflect its anonymous user-generated community features and moderation requirements, but it does not claim to provide in-app parental controls or age assurance.

Thank you.

## Verification

- In Age Ratings details, confirm `Parental Controls = None`.
- In Age Ratings details, confirm `Age Assurance = None`.
- Confirm `User-generated content` and community-related descriptors still match the app.
- Confirm Review Notes do not claim age verification, age assurance, parental controls, guardian controls, or equivalent functionality.
- A new binary is not required unless App Store Connect requires one for the resubmission flow.

## References

- [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [App Review Guidelines 2.3.6](https://developer.apple.com/app-store/review/guidelines/)
