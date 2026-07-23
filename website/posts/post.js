const API_URL = "https://us-central1-readify-403a6.cloudfunctions.net/getPublicPost";
const APP_STORE_URL = "https://apps.apple.com/ru/app/readbox-%D1%81%D1%82%D0%B0%D1%82%D1%8C%D0%B8-%D0%B8-%D0%B8-%D0%B8-%D0%B8%D1%81%D1%82%D0%BE%D1%80%D0%B8%D0%B8/id6745975985";

const locale = getLocale();

const I18N = {
    ru: {
        loading: "Загружаем публикацию...",
        unavailableTitle: "Публикация недоступна",
        unavailableText: "Не удалось открыть пост.",
        appStore: "Открыть App Store",
        openInApp: "Читать в приложении",
        missingIndex: "В ссылке нет параметра index.",
        premiumOnly: "Это premium-публикация. Её можно читать только в приложении.",
        notFound: "Пост не найден или уже недоступен.",
        loadError: "Не удалось загрузить пост. Проверьте URL функции и CORS.",
        untitled: "Без названия",
        article: "ARTICLE",
        post: "POST",
        authorFallback: "ReadBox author"
    },
    en: {
        loading: "Loading post...",
        unavailableTitle: "Post unavailable",
        unavailableText: "Could not open this post.",
        appStore: "Open App Store",
        openInApp: "Read in the app",
        missingIndex: "The link does not contain the index parameter.",
        premiumOnly: "This is a premium post. You can read it only in the app.",
        notFound: "This post was not found or is no longer available.",
        loadError: "Could not load the post. Check the function URL and CORS.",
        untitled: "Untitled",
        article: "ARTICLE",
        post: "POST",
        authorFallback: "ReadBox author"
    }
};

const loadingState = document.getElementById("loadingState");
const errorState = document.getElementById("errorState");
const errorText = document.getElementById("errorText");
const postView = document.getElementById("postView");

const authorAvatar = document.getElementById("authorAvatar");
const authorName = document.getElementById("authorName");
const checkmark = document.getElementById("checkmark");
const postType = document.getElementById("postType");
const postDate = document.getElementById("postDate");
const postTitle = document.getElementById("postTitle");
const heroMedia = document.getElementById("heroMedia");
const postContent = document.getElementById("postContent");

start();

async function start() {
    applyStaticTranslations();

    const params = new URLSearchParams(window.location.search);
    const postId = params.get("index");

    if (!postId) {
        showError(t("missingIndex"));
        return;
    }

    try {
        const response = await fetch(
            `${API_URL}?index=${encodeURIComponent(postId)}&lang=${encodeURIComponent(locale)}`,
            { method: "GET" }
        );

        const payload = await response.json().catch(() => ({}));

        if (!response.ok || !payload.post) {
            if (response.status === 403) {
                showError(t("premiumOnly"));
                return;
            }

            showError(t("notFound"));
            return;
        }

        await renderPost(payload.post);
    } catch (error) {
        console.error(error);
        showError(t("loadError"));
    }
}

async function renderPost(post) {
    document.title = post.title ? `${post.title} — ReadBox` : "ReadBox";

    postView.classList.remove("is-article", "is-post");
    postView.classList.add(post.isShortPost ? "is-post" : "is-article");

    authorName.textContent = post.authorName || t("authorFallback");
    renderAuthorAvatar(post);

    postType.textContent = post.isShortPost ? t("post") : t("article");
    postDate.textContent = formatDate(post.dateCreated);
    postTitle.textContent = post.title || t("untitled");

    if (post.isCheckmark) {
        checkmark.classList.remove("hidden");
    } else {
        checkmark.classList.add("hidden");
    }

    postContent.innerHTML = renderMarkdown(post.text || "");

    await renderMedia(post.media || []);
    applyMediaLayout(post);

    loadingState.classList.add("hidden");
    postView.classList.remove("hidden");

    updateAppButtons();
}

function renderAuthorAvatar(post) {
    const fallbackLetter = getInitial(post.authorName || "R");

    authorAvatar.innerHTML = "";
    authorAvatar.textContent = "";

    if (post.avatarUrl) {
        authorAvatar.innerHTML = `
            <img
                src="${post.avatarUrl}"
                alt="${escapeHtml(post.authorName || t("authorFallback"))}"
                style="
                    width: 46px;
                    height: 46px;
                    min-width: 46px;
                    min-height: 46px;
                    border-radius: 999px;
                    object-fit: cover;
                    display: block;
                "
            >
        `;
        return;
    }

    authorAvatar.textContent = fallbackLetter;
}

async function renderMedia(items) {
    heroMedia.innerHTML = "";
    heroMedia.style.removeProperty("--media-height");

    if (!Array.isArray(items) || items.length === 0) {
        heroMedia.classList.add("hidden");
        return;
    }

    const mediaWidth = Math.min(window.innerWidth - 48, 776);
    const carouselMaxHeight = Math.min(mediaWidth * 1.24, 600);
    const singleImageMaxHeight = 350;
    const singleVideoMaxHeight = 400;

    if (items.length === 1) {
        const item = items[0];
        const single = document.createElement("div");
        single.className = "single-media";

        const singleHeight = await resolveSingleMediaHeight(
            item,
            mediaWidth,
            singleImageMaxHeight,
            singleVideoMaxHeight
        );

        single.style.setProperty("--media-height", `${singleHeight}px`);
        single.appendChild(createMediaNode(item));
        heroMedia.appendChild(single);
        heroMedia.classList.remove("hidden");
        return;
    }

    const heights = await Promise.all(
        items.map((item) => resolveCarouselItemHeight(item, mediaWidth, carouselMaxHeight))
    );

    const resolvedHeight = Math.max(
        ...heights.filter(Boolean),
        Math.min(mediaWidth * 0.72, carouselMaxHeight)
    );

    heroMedia.style.setProperty("--media-height", `${resolvedHeight}px`);

    const carousel = document.createElement("div");
    carousel.className = "media-carousel";

    const track = document.createElement("div");
    track.className = "media-track";

    const counter = document.createElement("div");
    counter.className = "media-counter";
    counter.textContent = `1 / ${items.length}`;

    items.forEach((item) => {
        const slide = document.createElement("div");
        slide.className = "media-slide";
        slide.appendChild(createMediaNode(item));
        track.appendChild(slide);
    });

    track.addEventListener("scroll", () => {
        const index = Math.round(track.scrollLeft / Math.max(track.clientWidth, 1));
        counter.textContent = `${Math.min(index + 1, items.length)} / ${items.length}`;
    });

    carousel.appendChild(track);
    carousel.appendChild(counter);
    heroMedia.appendChild(carousel);
    heroMedia.classList.remove("hidden");
}

function createMediaNode(item) {
    if (item.type === "video") {
        const video = document.createElement("video");
        video.src = item.url;
        video.controls = true;
        video.playsInline = true;
        video.preload = "metadata";

        if (item.previewUrl) {
            video.poster = item.previewUrl;
        }

        return video;
    }

    const img = document.createElement("img");
    img.src = item.url;
    img.alt = "ReadBox media";
    img.loading = "lazy";
    return img;
}

function applyMediaLayout(post) {
    const mediaPosition = Number(post.mediaPosition ?? 0);
    const postHeader = document.querySelector(".post-header");
    const authorRow = document.querySelector(".author-row");

    if (!postHeader || !authorRow || heroMedia.classList.contains("hidden")) {
        return;
    }

    if (post.isShortPost && mediaPosition === 0) {
        authorRow.insertAdjacentElement("afterend", heroMedia);
        return;
    }

    if (mediaPosition === 1) {
        postContent.insertAdjacentElement("afterend", heroMedia);
    } else {
        postHeader.insertAdjacentElement("afterend", heroMedia);
    }
}

async function resolveSingleMediaHeight(item, width, imageMaxHeight, videoMaxHeight) {
    if (item.type === "video") {
        const size = await loadVideoSize(item.url);
        if (!size) return videoMaxHeight;
        return Math.min((width * size.height) / size.width, videoMaxHeight);
    }

    const size = await loadImageSize(item.url);
    if (!size) return imageMaxHeight;
    return Math.min((width * size.height) / size.width, imageMaxHeight);
}

async function resolveCarouselItemHeight(item, width, maxHeight) {
    if (item.type === "video") {
        const size = await loadVideoSize(item.url);
        if (!size) return maxHeight;
        return Math.min((width * size.height) / size.width, maxHeight);
    }

    const size = await loadImageSize(item.url);
    if (!size) return maxHeight;
    return Math.min((width * size.height) / size.width, maxHeight);
}

function loadImageSize(url) {
    return new Promise((resolve) => {
        const img = new Image();
        img.onload = () => resolve({ width: img.naturalWidth, height: img.naturalHeight });
        img.onerror = () => resolve(null);
        img.src = url;
    });
}

function loadVideoSize(url) {
    return new Promise((resolve) => {
        const video = document.createElement("video");
        video.preload = "metadata";
        video.onloadedmetadata = () => resolve({ width: video.videoWidth, height: video.videoHeight });
        video.onerror = () => resolve(null);
        video.src = url;
    });
}

function showError(message) {
    loadingState.classList.add("hidden");
    postView.classList.add("hidden");
    errorText.textContent = message;
    errorState.classList.remove("hidden");

    updateAppButtons();
}

function updateAppButtons() {
    for (const link of document.querySelectorAll(".app-button")) {
        link.href = APP_STORE_URL;
    }

    const appButtons = document.querySelectorAll(".app-button");
    if (appButtons[0]) {
        appButtons[0].textContent = t("appStore");
    }
    if (appButtons[1]) {
        appButtons[1].textContent = t("openInApp");
    }
}

function applyStaticTranslations() {
    document.documentElement.lang = locale;

    const loadingText = document.querySelector("#loadingState p");
    const errorTitle = document.querySelector("#errorState h1");

    if (loadingText) {
        loadingText.textContent = t("loading");
    }

    if (errorTitle) {
        errorTitle.textContent = t("unavailableTitle");
    }

    if (errorText) {
        errorText.textContent = t("unavailableText");
    }

    updateAppButtons();
}

function getLocale() {
    const params = new URLSearchParams(window.location.search);
    const forced = (params.get("lang") || "").toLowerCase();

    if (forced === "en" || forced === "ru") {
        return forced;
    }

    return (navigator.language || "").toLowerCase().startsWith("en") ? "en" : "ru";
}

function t(key) {
    return I18N[locale][key] || I18N.ru[key] || key;
}

function getInitial(name) {
    return String(name || "R").trim().charAt(0).toUpperCase() || "R";
}

function formatDate(value) {
    if (!value) return "";

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
        return "";
    }

    return new Intl.DateTimeFormat(locale === "en" ? "en-US" : "ru-RU", {
        day: "numeric",
        month: "long",
        year: "numeric"
    }).format(date);
}

function escapeHtml(value) {
    return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
}

function renderMarkdown(source) {
    const escaped = escapeHtml(source).replace(/\r\n/g, "\n");

    const html = escaped
        .replace(/!\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)/g, '<figure><img src="$2" alt="$1"></figure>')
        .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>')
        .replace(/^(#{1,6})\s+(.*?)\s*#*\s*$/gm, (_, hashes, content) => {
            const level = Math.min(hashes.length, 3);
            return `<h${level}>${content}</h${level}>`;
        })
        .replace(/\*\*([\s\S]+?)\*\*/g, "<strong>$1</strong>")
        .replace(/\*(.+?)\*/g, "<em>$1</em>")
        .replace(/`([^`]+)`/g, "<code>$1</code>");

    return html
        .split(/\n{2,}/)
        .map((block) => {
            const trimmed = block.trim();

            if (!trimmed) {
                return "";
            }

            if (/^<h[1-3]>/.test(trimmed) || /^<figure>/.test(trimmed)) {
                return trimmed;
            }

            if (/^(- |\* )/m.test(trimmed)) {
                const items = trimmed
                    .split("\n")
                    .filter((line) => /^(- |\* )/.test(line))
                    .map((line) => `<li>${line.replace(/^(- |\* )/, "")}</li>`)
                    .join("");

                return `<ul>${items}</ul>`;
            }

            return `<p>${trimmed.replace(/\n/g, "<br>")}</p>`;
        })
        .join("\n");
}