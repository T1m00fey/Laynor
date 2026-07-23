<?php
$url = 'https://us-central1-readify-403a6.cloudfunctions.net/sitemapXml';

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_TIMEOUT => 20,
    CURLOPT_HTTPHEADER => ['Accept: application/xml']
]);

$body = curl_exec($ch);
$status = curl_getinfo($ch, CURLINFO_RESPONSE_CODE) ?: 502;
$hasError = curl_errno($ch);
curl_close($ch);

if ($hasError || $body === false || $body === '') {
    http_response_code(502);
    header('Content-Type: text/plain; charset=utf-8');
    exit('upstream-error');
}

http_response_code($status);
header('Content-Type: application/xml; charset=utf-8');
echo $body;