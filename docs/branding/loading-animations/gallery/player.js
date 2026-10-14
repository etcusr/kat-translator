'use strict';
const videos = [...document.querySelectorAll('video')];
const button = document.querySelector('#play-all');
const status = document.querySelector('#play-status');
let playingAll = false;
let current = -1;
let generation = 0;
let failures = 0;

function highlight(video) {
  document.querySelectorAll('article').forEach(card => card.classList.toggle('current', card.contains(video)));
}
function stop(except = null) {
  playingAll = false;
  generation++;
  current = -1;
  videos.forEach(video => { if (video !== except) video.pause(); });
  button.textContent = 'Воспроизвести всё';
  button.setAttribute('aria-pressed', 'false');
  highlight(except);
  status.textContent = except ? except.dataset.title : 'Просмотр остановлен';
}
async function next() {
  const token = generation;
  if (!playingAll) return;
  current++;
  if (current >= videos.length) {
    stop();
    status.textContent = failures ? `Просмотр завершён. Не удалось открыть: ${failures}` : `Все ${videos.length} анимации просмотрены`;
    return;
  }
  const video = videos[current];
  videos.forEach(other => { if (other !== video) other.pause(); });
  video.loop = false;
  video.currentTime = 0;
  highlight(video);
  status.textContent = `${current + 1} / ${videos.length} · ${video.dataset.title}`;
  video.closest('article').scrollIntoView({behavior: 'instant', block: 'center'});
  try { await video.play(); }
  catch (error) {
    if (token !== generation || !playingAll || videos[current] !== video) return;
    failures++;
    await next();
  }
}
button.addEventListener('click', () => {
  if (playingAll) { stop(); return; }
  generation++;
  playingAll = true;
  failures = 0;
  current = -1;
  button.textContent = 'Остановить просмотр';
  button.setAttribute('aria-pressed', 'true');
  next();
});
videos.forEach(video => {
  video.addEventListener('error', () => {
    if (playingAll && videos[current] === video) { failures++; next(); }
  });
  video.addEventListener('ended', () => { if (playingAll && videos[current] === video) next(); });
  video.addEventListener('play', () => {
    if (playingAll && videos[current] === video) return;
    stop(video);
    video.loop = true;
  });
});
