<?php
$index = isset($_GET['index']) ? trim($_GET['index']) : '';

if ($index === '') {
    http_response_code(400);
    header('Content-Type: text/plain; charset=utf-8');
    exit('missing-index');
}

$url = 'https://us-central1-readify-403a6.cloudfunctions.net/renderPublicPostCard?index=' . rawurlencode($index);

if (isset($_GET['v'])) {
    $url .= '&v=' . rawurlencode(trim($_GET['v']));
}

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_TIMEOUT => 25,
    CURLOPT_HTTPHEADER => ['Accept: image/png,image/*']
]);

$body = curl_exec($ch);
$status = curl_getinfo($ch, CURLINFO_RESPONSE_CODE) ?: 502;
$contentType = curl_getinfo($ch, CURLINFO_CONTENT_TYPE) ?: 'image/png';
$hasError = curl_errno($ch);
curl_close($ch);

if ($hasError || $body === false || $body === '') {
    http_response_code(502);
    header('Content-Type: text/plain; charset=utf-8');
    exit('upstream-error');
}

http_response_code($status);
header('Content-Type: ' . $contentType);
header('Cache-Control: public, max-age=3600, s-maxage=86400');
header('X-Content-Type-Options: nosniff');
echo $body;
