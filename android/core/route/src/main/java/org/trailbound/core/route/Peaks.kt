package org.trailbound.core.route

/**
 * A hidden mountain card. Climb [heightM] metres in total on freezing walks (30°F or colder) and the peak reveals
 * itself; until then it shows as "???". Every cold step is 7 cm of virtual trail; real hills (barometer) add on top.
 */
data class Peak(
    val id: String,
    val name: String,
    val region: String,
    val heightM: Int,
    val quote: String,
    val facts: List<String>,
    /** The K2 easter egg: drawn as the Demon and awards the secret Crowley Award. */
    val demon: Boolean = false,
) {
    val heightFt: Int get() = (heightM * 3.28084).toInt()
}

/**
 * HIDDEN PEAKS: Mt Baker and Mt Rainier from home turf, then the Seven Summits (both versions: Kosciuszko and
 * Puncak Jaya) in order of height, with K2 hidden just below Everest. Heights are the commonly cited surveys.
 */
object Peaks {
    const val TITLE = "HIDDEN PEAKS · climb counts only on freezing walks"

    val all: List<Peak> = listOf(
        Peak(
            "kosciuszko", "Mount Kosciuszko", "Australia · Seven Summits", 2_228, "Every summit starts small.",
            listOf(
                "Australia's highest point, and the easiest of the Seven Summits.",
                "1840: Named by Polish explorer Paweł Strzelecki after freedom fighter Tadeusz Kościuszko.",
                "Some climbers count Puncak Jaya as Oceania's summit instead; this deck has both.",
            ),
        ),
        Peak(
            "baker", "Mount Baker", "Washington, USA", 3_286, "Snow first, summit later.",
            listOf(
                "Koma Kulshan to the Lummi and Nooksack peoples; an active, glacier-covered volcano.",
                "1868: First recorded ascent, by Edmund Coleman's party.",
                "1998–99: The Mt. Baker ski area recorded 1,140 inches of snow, a world record for one season.",
            ),
        ),
        Peak(
            "rainier", "Mount Rainier", "Washington, USA", 4_392, "The mountain decides.",
            listOf(
                "Tahoma (or Tacoma) to the Puyallup and other Coast Salish peoples; 14,410 ft.",
                "The most glaciated peak in the contiguous United States, and an active volcano.",
                "1870: First recorded ascent, by Hazard Stevens and Philemon Van Trump.",
            ),
        ),
        Peak(
            "puncak-jaya", "Puncak Jaya", "Papua, Indonesia · Seven Summits", 4_884, "Ice on the equator.",
            listOf(
                "Also called Carstensz Pyramid: the highest island peak in the world.",
                "Its small glaciers sit almost on the equator and are shrinking fast.",
                "1962: First ascent, by Heinrich Harrer's team (of Seven Years in Tibet).",
            ),
        ),
        Peak(
            "vinson", "Vinson Massif", "Antarctica · Seven Summits", 4_892, "Nobody lives here. Keep walking.",
            listOf(
                "The highest point in Antarctica, about 1,200 km from the South Pole.",
                "First seen from the air only in 1958.",
                "Dec 1966: First ascent, by an American expedition led by Nicholas Clinch.",
            ),
        ),
        Peak(
            "elbrus", "Mount Elbrus", "Caucasus, Russia · Seven Summits", 5_642, "Two summits, one cold wind.",
            listOf(
                "A dormant volcano with twin summits; the west summit is the higher.",
                "1829: First ascent of the east summit, credited to Khillar Khachirov.",
                "1874: A British party led by Florence Crauford Grove reaches the west summit.",
            ),
        ),
        Peak(
            "kilimanjaro", "Kilimanjaro", "Tanzania · Seven Summits", 5_895, "Pole pole: slowly, slowly.",
            listOf(
                "The highest free-standing mountain on Earth, rising from the African plains.",
                "1889: First recorded ascent, by Hans Meyer and Ludwig Purtscheller, guided by Yohani Lauwo.",
                "Climbers pass through rainforest, moorland and alpine desert to reach the snow.",
            ),
        ),
        Peak(
            "denali", "Denali · Mount McKinley", "Alaska, USA · Seven Summits", 6_190, "The High One.",
            listOf(
                "One mountain, two names: Denali (\"the high one\" in Koyukon) and Mount McKinley.",
                "1917: Federally named McKinley; 2015: renamed Denali; 2025: federally McKinley again. Alaska keeps Denali.",
                "1913: First ascent, by Hudson Stuck, Harry Karstens, Robert Tatum and Walter Harper, the first to the top.",
                "Measured base to peak, it's taller than Everest.",
            ),
        ),
        Peak(
            "aconcagua", "Aconcagua", "Argentina · Seven Summits", 6_961, "Thin air, long road.",
            listOf(
                "The highest mountain outside Asia, in the Andes.",
                "1897: First recorded ascent, by Swiss guide Matthias Zurbriggen.",
                "An Inca mummy found on its slopes shows people climbed high here long before.",
            ),
        ),
        Peak(
            "k2", "K2 · The Savage Mountain", "Karakoram, Pakistan–China", 8_611, "Do what thou wilt. The mountain will too.",
            listOf(
                "The second-highest mountain on Earth, and by far the deadlier of the two highest.",
                "1902: Oscar Eckenstein and Aleister Crowley lead the first serious attempt, reaching about 6,500 m.",
                "Crowley, the occultist later called \"the wickedest man in the world\", went on to lead a 1905 Kangchenjunga attempt.",
                "1954: First ascent, by Italians Lino Lacedelli and Achille Compagnoni.",
                "Jan 2021: A team of ten Nepali climbers makes the first winter ascent.",
            ),
            demon = true,
        ),
        Peak(
            "everest", "Mount Everest", "Nepal–China · Seven Summits", 8_849, "The roof of the world. You walked here.",
            listOf(
                "Chomolungma in Tibetan, Sagarmatha in Nepali; 8,849 m by the 2020 China–Nepal survey.",
                "May 29, 1953: Tenzing Norgay and Edmund Hillary reach the summit.",
                "The end of the deck: climb its height on freezing walks and you've climbed Everest.",
            ),
        ),
    )
}
