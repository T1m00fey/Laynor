const API_URL = "https://us-central1-readify-403a6.cloudfunctions.net/getHomepagePosts";

const locale = navigator.language.toLowerCase().startsWith("ru") ? "ru" : "en";

const I18N = {
    ru: {
        headerButton: "Скачать",
        eyebrow: "Чтение без лишнего шума",
        title: "Истории и идеи, к которым хочется вернуться.",
        subtitle: "Читайте публикации любимых каналов и делитесь собственными мыслями в ReadBox.",
        appStore: "Открыть в App Store",
        insideReadBox: "Внутри ReadBox",
        publicationsTitle: "Публикации для знакомства",
        refresh: "Другие публикации",
        privacy: "Конфиденциальность",
        terms: "Условия использования",
        loadingError: "Не удалось загрузить публикации. Попробуйте немного позже.",
        empty: "Пока здесь нет доступных публикаций.",
        article: "Статья",
        post: "Пост",
        authorFallback: "Автор ReadBox",
        untitled: "Без названия",
        expand: "Развернуть ↓"
    },
    en: {
        headerButton: "Download",
        eyebrow: "Reading without the noise",
        title: "Stories and ideas worth coming back to.",
        subtitle: "Follow publications from channels you enjoy and share your own thoughts in ReadBox.",
        appStore: "Open in the App Store",
        insideReadBox: "Inside ReadBox",
        publicationsTitle: "Publications to start with",
        refresh: "Show other posts",
        privacy: "Privacy",
        terms: "Terms of use",
        loadingError: "Could not load publications. Please try again later.",
        empty: "There are no public posts here yet.",
        article: "Article",
        post: "Post",
        authorFallback: "ReadBox author",
        untitled: "Untitled",
        expand: "Expand ↓"
    }
};

const publicationGrid = document.getElementById("publicationGrid");
const publicationsStatus = document.getElementById("publicationsStatus");
const refreshButton = document.getElementById("refreshButton");

applyTranslations();
loadPublications();

refreshButton.addEventListener("click", () => loadPublications(true));

async function loadPublications(forceRefresh = false) {
    setLoadingState();

    try {
        const requestURL = new URL(API_URL);
        requestURL.searchParams.set("lang", locale);

        if (forceRefresh) {
            requestURL.searchParams.set("refresh", Date.now().toString());
        }

        const response = await fetch(requestURL, {
            method: "GET",
            headers: { "Accept": "application/json" }
        });
        const payload = await response.json().catch(() => ({}));

        if (!response.ok) {
            throw new Error(payload.error || "request-failed");
        }

        const posts = Array.isArray(payload.posts) ? payload.posts : [];

        if (posts.length === 0) {
            showStatus(t("empty"));
            return;
        }

        const cards = await Promise.all(posts.map((post) => createPublicationCard(post)));

        publicationGrid.innerHTML = "";
        cards.forEach((card) => publicationGrid.appendChild(card));
        publicationGrid.classList.remove("hidden");
        publicationsStatus.classList.add("hidden");
        refreshButton.disabled = false;
    } catch (error) {
        console.error(error);
        showStatus(t("loadingError"));
    }
}

function setLoadingState() {
    refreshButton.disabled = true;
    publicationsStatus.classList.add("hidden");
    publicationGrid.classList.remove("hidden");
    publicationGrid.innerHTML = Array.from({ length: 5 }, () => (
        '<article class="publication-card skeleton" aria-hidden="true"></article>'
    )).join("");
}

function showStatus(message) {
    publicationGrid.classList.add("hidden");
    publicationsStatus.textContent = message;
    publicationsStatus.classList.remove("hidden");
    refreshButton.disabled = false;
}

async function createPublicationCard(post) {
    const card = document.createElement("article");
    card.className = `publication-card ${post.isShortPost ? "is-post" : "is-article"}`;

    const link = document.createElement("a");
    link.className = "publication-link";
    link.href = `/posts/?index=${encodeURIComponent(post.id || "")}`;
    link.setAttribute("aria-label", getCardText(post) || t("untitled"));

    const header = createCardHeader(post);
    const title = createTitleSection(post);
    const media = await createMediaSection(post);
    const mediaPosition = Number(post.mediaPosition || 0);

    link.appendChild(header);

    if (post.isShortPost && mediaPosition === 1 && title) {
        if (media) {
            title.classList.add("before-media");
        }

        link.appendChild(title);
    }

    if (media) {
        link.appendChild(media);
    }

    if (title && (mediaPosition === 0 || !post.isShortPost)) {
        if (media) {
            title.classList.add("after-media");
        }

        link.appendChild(title);
    }

    if (post.isShortPost) {
        link.appendChild(createActionRow());
    }

    card.appendChild(link);
    return card;
}

function createCardHeader(post) {
    const header = document.createElement("header");
    header.className = "post-header";
    header.appendChild(createAuthorRow(post));
    return header;
}

function createTitleSection(post) {
    const text = getCardText(post);

    if (!text) return null;

    const section = document.createElement("section");
    section.className = "title-section";

    if (text.length >= 250) {
        section.classList.add("is-collapsed");
    }

    const title = document.createElement("div");
    title.className = "post-title";
    title.innerHTML = renderTitleText(text);
    section.appendChild(title);

    if (text.length >= 250) {
        const fade = document.createElement("div");
        fade.className = "title-fade";
        fade.appendChild(document.createElement("span")).textContent = t("expand");
        section.appendChild(fade);
    }

    return section;
}

async function createMediaSection(post) {
    const items = getMediaItems(post);

    if (items.length === 0) return null;

    const section = document.createElement("section");
    section.className = "hero-media";

    const cardWidth = window.innerWidth > 700
        ? Math.min(window.innerWidth - 80, 620)
        : Math.min(window.innerWidth - 10, 430);
    const mediaWidth = cardWidth - 30;
    const carouselMaxHeight = Math.min(mediaWidth * 1.12, 450);
    const singleImageMaxHeight = window.innerWidth > 700 ? 430 : 350;
    const singleVideoMaxHeight = window.innerWidth > 700 ? 460 : 400;

    section.style.setProperty("--media-width", `${mediaWidth}px`);

    if (items.length === 1) {
        const item = items[0];
        const single = document.createElement("div");
        single.className = "single-media";

        const height = await resolveSingleMediaHeight(
            item,
            mediaWidth,
            singleImageMaxHeight,
            singleVideoMaxHeight
        );

        single.style.setProperty("--media-height", `${height}px`);
        single.appendChild(createMediaNode(item));
        section.appendChild(single);
        return section;
    }

    const heights = await Promise.all(
        items.map((item) => resolveCarouselItemHeight(item, mediaWidth, carouselMaxHeight))
    );
    const height = Math.max(
        ...heights.filter(Boolean),
        Math.min(mediaWidth * 0.72, carouselMaxHeight)
    );

    section.style.setProperty("--media-height", `${height}px`);

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

    carousel.append(track, counter);
    section.appendChild(carousel);
    return section;
}

function getMediaItems(post) {
    if (Array.isArray(post.media) && post.media.length > 0) {
        return post.media.filter((item) => item && item.url);
    }

    if (post.previewUrl) {
        return [{ type: "image", url: post.previewUrl }];
    }

    return [];
}

function createMediaNode(item) {
    const wrapper = document.createElement("div");
    wrapper.className = "media-preview";

    if (item.type === "video") {
        wrapper.classList.add("is-video");

        const video = document.createElement("video");
        video.src = item.url;
        video.playsInline = true;
        video.muted = true;
        video.preload = "metadata";

        if (item.previewUrl) {
            video.poster = item.previewUrl;
        }

        wrapper.appendChild(video);
        wrapper.appendChild(createPlayIcon());
        return wrapper;
    }

    const image = document.createElement("img");
    image.src = item.url;
    image.alt = "ReadBox media";
    image.loading = "lazy";
    wrapper.appendChild(image);
    return wrapper;
}

function createPlayIcon() {
    const icon = document.createElement("span");
    icon.className = "video-play-icon";
    icon.setAttribute("aria-hidden", "true");
    return icon;
}

function createAuthorRow(post) {
    const row = document.createElement("div");
    row.className = "author-row";

    if (post.avatarUrl) {
        const avatar = document.createElement("div");
        avatar.className = "author-avatar";
        const image = document.createElement("img");
        image.className = "author-avatar-image";
        image.src = post.avatarUrl;
        image.alt = "";
        image.loading = "lazy";
        avatar.appendChild(image);
        row.appendChild(avatar);
    }

    const copy = document.createElement("div");
    copy.className = "author-meta";

    const authorLine = document.createElement("div");
    authorLine.className = "author-name-row";

    const name = document.createElement("span");
    name.className = "author-name";
    name.textContent = post.authorName || t("authorFallback");
    authorLine.appendChild(name);

    if (post.isCheckmark) {
        const checkmark = document.createElement("img");
        checkmark.className = "checkmark";
        checkmark.src = "/images/checkmark.webp";
        checkmark.alt = "Verified";
        authorLine.appendChild(checkmark);
    }

    const date = document.createElement("span");
    date.className = "meta-date";
    date.textContent = formatDate(post.dateCreated);

    const meta = document.createElement("div");
    meta.className = "meta-row";
    meta.appendChild(date);

    copy.append(authorLine, meta);
    row.appendChild(copy);

    if (!post.isShortPost) {
        row.appendChild(createArticleBadge());
    }

    return row;
}

function createArticleBadge() {
    const badge = document.createElement("span");
    badge.className = "article-badge";
    badge.textContent = t("article").toUpperCase();
    return badge;
}

function createActionRow() {
    const row = document.createElement("div");
    row.className = "card-actions";
    row.setAttribute("aria-hidden", "true");

    row.append(
        createIcon("M7 10v11H3V10h4Zm0 10h10.2a2 2 0 0 0 1.94-1.52l1.5-6A2 2 0 0 0 18.7 10H14l.7-3.1A3 3 0 0 0 11.8 3L7 10Z"),
        createIcon("M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4v8Z")
    );

    const share = createIcon("M15 3l6 6-6 6v-4c-5 0-8 2-11 7 1-7 5-11 11-11V3Z");
    share.classList.add("action-share");
    row.appendChild(share);
    return row;
}

function getCardText(post) {
    return String(post.title || "").trim();
}

function createIcon(pathData) {
    const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    icon.classList.add("card-action-icon");
    icon.setAttribute("viewBox", "0 0 24 24");

    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", pathData);
    icon.appendChild(path);
    return icon;
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

function applyTranslations() {
    document.documentElement.lang = locale;
    document.querySelectorAll("[data-i18n]").forEach((element) => {
        element.textContent = t(element.dataset.i18n);
    });
}

function formatDate(value) {
    if (!value) return "";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "";

    const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000));

    if (seconds < 3600) {
        const minutes = Math.max(1, Math.floor(seconds / 60));
        return locale === "ru"
            ? `${minutes} ${russianPlural(minutes, "минуту", "минуты", "минут")} назад`
            : `${minutes} minute${minutes === 1 ? "" : "s"} ago`;
    }

    if (seconds < 86400) {
        const hours = Math.floor(seconds / 3600);
        return locale === "ru"
            ? `${hours} ${russianPlural(hours, "час", "часа", "часов")} назад`
            : `${hours} hour${hours === 1 ? "" : "s"} ago`;
    }

    if (seconds < 31 * 86400) {
        const days = Math.floor(seconds / 86400);
        return locale === "ru"
            ? `${days} ${russianPlural(days, "день", "дня", "дней")} назад`
            : `${days} day${days === 1 ? "" : "s"} ago`;
    }

    return new Intl.DateTimeFormat(locale === "ru" ? "ru-RU" : "en-US", {
        day: "numeric",
        month: "long",
        year: date.getFullYear() === new Date().getFullYear() ? undefined : "2-digit"
    }).format(date);
}

function russianPlural(value, one, few, many) {
    const mod100 = value % 100;
    const mod10 = value % 10;

    if (mod100 >= 11 && mod100 <= 14) return many;
    if (mod10 === 1) return one;
    if (mod10 >= 2 && mod10 <= 4) return few;
    return many;
}

function escapeHtml(value) {
    return String(value || "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
}

function renderTitleText(source) {
    return escapeHtml(source)
        .replace(/\r\n/g, "\n")
        .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<span class="inline-link">$1</span>')
        .replace(/\*\*([\s\S]+?)\*\*/g, "<strong>$1</strong>")
        .replace(/\*(.+?)\*/g, "<em>$1</em>")
        .replace(/`([^`]+)`/g, "<code>$1</code>")
        .replace(/\n/g, "<br>");
}

function renderMarkdown(source) {
    const escaped = escapeHtml(source).replace(/\r\n/g, "\n");

    if (!escaped.trim()) {
        return "";
    }

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

function t(key) {
    return I18N[locale]?.[key] || I18N.ru[key] || key;
}
