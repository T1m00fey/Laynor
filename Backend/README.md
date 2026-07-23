# Laynor Firebase backend

Firebase project: `factorial-9c9f3`  
Region: `europe-west1`  
Functions: `budyRewrite`, `budyFeedback`

## First deploy

```bash
cd /Users/tim_yud/Documents/BudyAI/Backend/functions
npm install

cd ..
firebase login
firebase use factorial-9c9f3
firebase functions:secrets:set BUDY_OPENAI_API_KEY
firebase deploy --only functions:budy:budyRewrite,functions:budy:budyFeedback
```

For `BUDY_OPENAI_API_KEY`, paste the OpenAI project API key. Never put it into the iOS app. The MVP client identifier is compiled into both the function and the app, so users configure nothing.

Production endpoint:

```text
https://europe-west1-factorial-9c9f3.cloudfunctions.net/budyRewrite
https://europe-west1-factorial-9c9f3.cloudfunctions.net/budyFeedback
```

Feedback from the app is validated by `budyFeedback` and saved to the
`feedback` Firestore collection with the status `new`. The app has no direct
write access to Firestore.

## Local emulator

Create `functions/.secret.local` (it is gitignored):

```dotenv
BUDY_OPENAI_API_KEY=sk-...
```

Then run:

```bash
firebase emulators:start --only functions
```
