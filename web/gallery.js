const grid = document.querySelector('#examples');
const search = document.querySelector('#search');
const buttons = [...document.querySelectorAll('[data-category]')];
let category = 'Все';
try {
  const response = await fetch('examples.json');
  if (!response.ok) throw new Error('Не удалось загрузить список примеров');
  const examples = await response.json();
  document.querySelector('#total').textContent = examples.length;
  const cards = examples.map((demo, index) => {
    const card = document.createElement('article'); card.className = 'card';
    const link = document.createElement('a'); link.className = 'preview'; link.href = `example.html?demo=${encodeURIComponent(demo.id)}`;
    link.setAttribute('aria-label', `Открыть ${demo.title}`);
    const image = new Image(); image.src = demo.image; image.alt = `Интерфейс ${demo.title}`;
    image.width = 1200; image.height = 820; image.loading = index < 3 ? 'eager' : 'lazy';
    link.append(image);
    const launch = document.createElement('span'); launch.className = 'launch'; launch.textContent = 'Открыть пример ↗'; link.append(launch);
    const body = document.createElement('div'); body.className = 'card-body';
    const caption = document.createElement('p'); caption.className = 'category'; caption.textContent = demo.category;
    const heading = document.createElement('h2'); const title = document.createElement('a'); title.href = link.href; title.textContent = demo.title; heading.append(title);
    const description = document.createElement('p'); description.className = 'description'; description.textContent = demo.description;
    const tags = document.createElement('div'); tags.className = 'tags';
    for (const text of demo.tags) { const tag = document.createElement('span'); tag.textContent = text; tags.append(tag); }
    body.append(caption, heading, description, tags); card.append(link, body); grid.append(card);
    return {demo, card, text: `${demo.title} ${demo.description} ${demo.tags.join(' ')}`.toLocaleLowerCase()};
  });
  function filter() {
    const query = search.value.trim().toLocaleLowerCase(); let count = 0;
    for (const entry of cards) {
      const show = (category === 'Все' || entry.demo.category === category) && entry.text.includes(query);
      entry.card.hidden = !show; count += Number(show);
    }
    document.querySelector('#count').textContent = `Показано ${count} из ${examples.length}`;
    document.querySelector('#empty').hidden = count !== 0;
  }
  for (const button of buttons) button.addEventListener('click', () => {
    category = button.dataset.category;
    for (const item of buttons) { const active = item === button; item.classList.toggle('active', active); item.setAttribute('aria-pressed', active); }
    filter();
  });
  search.addEventListener('input', filter); filter();
} catch (error) { document.querySelector('#count').textContent = error.message; }
