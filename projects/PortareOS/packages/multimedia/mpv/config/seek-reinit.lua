-- Re-create the video decoder after every seek while the hardware decoder
-- is in use. On the Nova (Qualcomm iris, ffmpeg v4l2m2m) a seek leaves the
-- decoder stuck: the picture freezes while the audio plays on. Re-creating
-- it costs a few frames and works in both directions. Interim until the
-- ffmpeg flush fix (portareos#301) is in; then this file goes.
mp.register_event("seek", function()
  if mp.get_property("hwdec-current") == "v4l2m2m-copy" then
    mp.set_property("hwdec", "no")
    mp.set_property("hwdec", "v4l2m2m-copy")
  end
end)
