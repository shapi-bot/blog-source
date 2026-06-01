// 全局APlayer播放器配置
// 使用Meting.js加载网易云歌单

document.addEventListener('DOMContentLoaded', function() {
    // 创建播放器容器
    const playerContainer = document.createElement('div');
    playerContainer.id = 'global-aplayer';
    document.body.appendChild(playerContainer);
    
    // 使用meting标签方式加载
    const metingDiv = document.createElement('div');
    metingDiv.className = 'aplayer';
    metingDiv.setAttribute('data-id', '3778678');
    metingDiv.setAttribute('data-server', 'netease');
    metingDiv.setAttribute('data-type', 'playlist');
    metingDiv.setAttribute('data-fixed', 'true');
    metingDiv.setAttribute('data-autoplay', 'false');
    metingDiv.setAttribute('data-theme', '#ad7a86');
    metingDiv.setAttribute('data-volume', '0.7');
    metingDiv.setAttribute('data-mutex', 'true');
    metingDiv.setAttribute('data-list-folded', 'true');
    metingDiv.setAttribute('data-list-max-height', '300px');
    metingDiv.setAttribute('data-preload', 'none');
    playerContainer.appendChild(metingDiv);
    
    // 如果Meting.js已加载，手动触发
    if (typeof Meting !== 'undefined') {
        Meting.init();
    }
});
