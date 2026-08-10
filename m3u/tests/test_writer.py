import m3u


def test_roundtrip_extended():
    pl = m3u.Playlist()
    pl.append("song1.mp3", title="First", duration=120)
    pl.append("http://example.com/stream", title="Live", duration=-1, **{"tvg-id": "ch1"})

    text = pl.dumps(extended=True)
    reparsed = m3u.parse(text)

    assert reparsed == pl
    assert reparsed[0].title == "First"
    assert reparsed[1].attributes["tvg-id"] == "ch1"


def test_extended_header_present():
    pl = m3u.Playlist()
    pl.append("a.mp3", title="A", duration=10)
    text = pl.dumps(extended=True)
    assert text.startswith("#EXTM3U\n")
    assert "#EXTINF:10,A" in text


def test_simple_output_has_no_metadata():
    pl = m3u.Playlist()
    pl.append("a.mp3", title="A", duration=10)
    pl.append("b.mp3", title="B", duration=20)
    text = pl.dumps(extended=False)
    assert "#EXTINF" not in text
    assert "#EXTM3U" not in text
    assert text.strip().splitlines() == ["a.mp3", "b.mp3"]


def test_write_and_read_file(tmp_path):
    pl = m3u.Playlist()
    pl.append("song.mp3", title="Song", duration=42)

    out = tmp_path / "list.m3u"
    pl.write_file(str(out))

    loaded = m3u.parse_file(str(out))
    assert loaded == pl
