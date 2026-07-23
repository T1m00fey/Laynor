<?php
$index = isset($_GET['index']) ? trim($_GET['index']) : '';

if ($index === '') {
    http_response_code(400);
    header('Content-Type: text/plain; charset=utf-8');
    exit('missing-index');
}

$url = 'https://us-central1-readify-403a6.cloudfunctions.net/renderPublicPostPage?index=' . rawurlencode($index);

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_TIMEOUT => 20,
    CURLOPT_HTTPHEADER => ['Accept: text/html']
]);

$body = curl_exec($ch);
$status = curl_getinfo($ch, CURLINFO_RESPONSE_CODE) ?: 502;
$contentType = curl_getinfo($ch, CURLINFO_CONTENT_TYPE) ?: 'text/html; charset=utf-8';
$hasError = curl_errno($ch);
curl_close($ch);

if ($hasError || $body === false || $body === '') {
    http_response_code(502);
    header('Content-Type: text/plain; charset=utf-8');
    exit('upstream-error');
}

$cardUrl = 'https://readbox.online/posts/card.php?index=' . rawurlencode($index) . '&v=6';
$body = preg_replace(
    '/https:\/\/us-central1-readify-403a6\.cloudfunctions\.net\/renderPublicPostCard\?index=[^"\']*/',
    $cardUrl,
    $body
);

http_response_code($status);
header('Content-Type: ' . $contentType);
echo $body;
