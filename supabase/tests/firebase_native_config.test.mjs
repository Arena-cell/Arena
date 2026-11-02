import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '../..');
for (const [app, androidId, iosId] of [
  ['playon', 'com.example.playon', 'com.example.playon'],
  ['arena_owner', 'com.playon.arena_owner', 'com.playon.arenaOwner'],
]) {
  const appRoot = path.resolve(root, '..', app);
  test(`${app}: server click action resolves to declared launcher activity`, () => {
    const manifest = fs.readFileSync(path.join(appRoot, 'android/app/src/main/AndroidManifest.xml'), 'utf8');
    const activity = manifest.match(/<activity[\s\S]*?<\/activity>/)?.[0];
    assert.ok(activity?.includes('android:name=".MainActivity"'));
    assert.match(activity, /<intent-filter>\s*<action android:name="FLUTTER_NOTIFICATION_CLICK"\s*\/>\s*<category android:name="android.intent.category.DEFAULT"\s*\/>\s*<\/intent-filter>/);
  });
  test(`${app}: Firebase project/package and iOS resource graph agree`, () => {
    const config = JSON.parse(fs.readFileSync(path.join(appRoot, 'android/app/google-services.json')));
    assert.equal(config.project_info.project_id, 'arena-staging-ae20f');
    assert.ok(config.client.some(c => c.client_info.android_client_info.package_name === androidId));
    const plist = fs.readFileSync(path.join(appRoot, 'ios/Runner/GoogleService-Info.plist'), 'utf8');
    assert.match(plist, new RegExp(`<key>BUNDLE_ID<\/key>\\s*<string>${iosId.replaceAll('.', '\\.')}<\/string>`));
    const project = fs.readFileSync(path.join(appRoot, 'ios/Runner.xcodeproj/project.pbxproj'), 'utf8');
    assert.match(project, /PBXBuildFile; fileRef = FC1000000000000000000002/);
    assert.match(project, /children = \(\s*FC1000000000000000000002/);
    assert.match(project, /files = \(\s*FC1000000000000000000001/);
    assert.equal((project.match(/CODE_SIGN_ENTITLEMENTS = Runner\/Runner.entitlements;/g) ?? []).length, 3);
    assert.equal((project.match(/APS_ENVIRONMENT = development;/g) ?? []).length, 1);
    assert.equal((project.match(/APS_ENVIRONMENT = production;/g) ?? []).length, 2);
    const info = fs.readFileSync(path.join(appRoot, 'ios/Runner/Info.plist'), 'utf8');
    assert.match(info, /<key>UIBackgroundModes<\/key>\s*<array>\s*<string>remote-notification<\/string>/);
  });
}
