//
//  GetSelection.js
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

// Runs in the Safari page context to collect the current selection & page info.
var GetSelection = function() {};

GetSelection.prototype = {
    run: function (arguments) {
        try {
            const selection = (window.getSelection && window.getSelection().toString()) || '';
            const payload = {
                selection: selection,
                title: document.title || '',
                url: document.location ? document.location.href : ''
            };
            arguments.completionFunction(payload);
        } catch (e) {
            arguments.completionFunction({ selection: '', title: '', url: '', error: String(e) });
        }
    },
    finalize: function (arguments) {
        // No-op
    }
};

var ExtensionPreprocessingJS = new GetSelection();
