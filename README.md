# aniz

aniz is a program for keeping a local list of anime you have watched. It ships with an anime
database embedded in the executable, so it does not require an internet connection to function.
You need to update it to get an up to date anime database.


## Example

```sh
$ # Search for an anime in the database
$ aniz database -s 'Attack on titan' | head -n1
tv      2013    spring  25      Shingeki no Kyojin      https://anidb.net/anime/9541    https://cdn.myanimelist.net/images/anime/10/47347.jpg

$ # Add one or more animes to your list
$ aniz plan-to-watch \
    https://anidb.net/anime/9541 \
    https://anilist.co/anime/11981 \
    https://kitsu.io/anime/7929

$ # Show your list
$ aniz list
2023-04-19      p       0       0       Shingeki no Kyojin      https://anidb.net/anime/9541
2023-04-19      p       0       0       RWBY    https://kitsu.io/anime/7929
2023-04-19      p       0       0       Mahou Shoujo Madoka★Magica Movie 3: Hangyaku no Monogatari        https://anilist.co/anime/11981

$ # Watch an episode
$ aniz watch-episode https://kitsu.io/anime/7929
$ aniz list
2023-04-19      w       1       0       RWBY    https://kitsu.io/anime/7929
2023-04-19      p       0       0       Shingeki no Kyojin      https://anidb.net/anime/9541
2023-04-19      p       0       0       Mahou Shoujo Madoka★Magica Movie 3: Hangyaku no Monogatari        https://anilist.co/anime/11981

$ # Complete show
$ aniz complete https://anidb.net/anime/9541
$ aniz list
2023-04-19      w       1       0       RWBY    https://kitsu.io/anime/7929
2023-04-19      p       0       0       Mahou Shoujo Madoka★Magica Movie 3: Hangyaku no Monogatari        https://anilist.co/anime/11981
2023-04-19      c       25      1       Shingeki no Kyojin      https://anidb.net/anime/9541

```


