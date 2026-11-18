const assert = require('node:assert/strict');
const { youtubeDestination } = require('./.build/youtubeLinks.js');
assert.equal(youtubeDestination(''), 'https://m.youtube.com/');
assert.equal(youtubeDestination('Daft Punk One More Time'), 'https://m.youtube.com/results?search_query=Daft%20Punk%20One%20More%20Time');
assert.equal(youtubeDestination('https://youtu.be/dQw4w9WgXcQ'), 'https://m.youtube.com/watch?v=dQw4w9WgXcQ');
assert.equal(youtubeDestination('https://m.youtube.com/watch?v=dQw4w9WgXcQ'), 'https://m.youtube.com/watch?v=dQw4w9WgXcQ');
assert.equal(youtubeDestination('https://evil.example/watch?v=foo'), 'https://m.youtube.com/results?search_query=https%3A%2F%2Fevil.example%2Fwatch%3Fv%3Dfoo');
console.log('YouTube URL tests passed');
