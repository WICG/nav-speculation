# Prerendering browsing contexts

TODO placeholder. Grab stuff from portals.

* apply mitigations as above to subresource and scripted fetches
* deny scripted access to unpartitioned storage, such as cookies and IndexedDB
* deny permission to invoke `window.alert`, autoplay audio, and other APIs inappropriate at this time

JS API probably belongs here (maybe it should use page visibility API instead):

## JavaScript API

Script can observe and react to changes in the loading mode, if applicable. For example, it can observe a change from `uncredentialed-prerender` to `default` when a user navigates to the prerendered document. This can be used to defer personalization and logic which are not necessary for prerendering.

```js
function afterPrerendering() { /* ... */ }

if (!document.loadingMode || document.loadingMode.type === 'default') {
    afterPrerendering();
} else {
    document.addEventListener('loadingmodechange', () => {
        if (document.loadingMode.type === 'default')
            afterPrerendering();
    });
}
```

Script can also observe this by using APIs particular to the behavior they are interested in. For instance, the [`document.hasStorageAccess()`](https://github.com/privacycg/storage-access) API can be used in supporting browsers to observe whether unpartitioned storage is available.
