import m3u


PLAIN = """
song1.mp3
song2.mp3
http://example.com/stream
""".strip()

EXTENDED = """#EXTM3U
#EXTINF:210,Artist - First Song
song1.mp3
#EXTINF:-1 tvg-id="ch1" group-title="News",Live Channel
http://example.com/stream
""".strip()


def test_parse_plain():
    pl = m3u.parse(PLAIN)
    assert len(pl) == 3
    assert pl[0].path == "song1.mp3"
    assert pl[0].title is None
    assert pl[2].is_stream is True


def test_parse_extended_metadata():
    pl = m3u.parse(EXTENDED)
    assert len(pl) == 2
    assert pl[0].duration == 210
    assert pl[0].title == "Artist - First Song"
    assert pl[0].path == "song1.mp3"


def test_parse_extinf_attributes():
    pl = m3u.parse(EXTENDED)
    stream = pl[1]
    assert stream.duration == -1
    assert stream.title == "Live Channel"
    assert stream.attributes["tvg-id"] == "ch1"
    assert stream.attributes["group-title"] == "News"


def test_blank_and_comment_lines_ignored():
    text = "#EXTM3U\n\n# a comment\nsong.mp3\n\n"
    pl = m3u.parse(text)
    assert len(pl) == 1
    assert pl[0].path == "song.mp3"


def test_total_duration():
    pl = m3u.parse(EXTENDED)
    # 210 known + one stream (-1, excluded) -> 210
    assert pl.total_duration == 210
