package org.trailbound.core.route

/**
 * Walk for Freedom · The North Star, Chapter 1: Dorchester County, Maryland to Philadelphia.
 * Follows the general corridor Harriet Tubman and many other freedom seekers travelled north through the
 * Delmarva Peninsula. Coordinates are approximate town centres, not exact historical paths.
 *
 * DRAFT COPY: needs historian / sensitivity review before release (see README risk register, P3).
 * Framing rule: places and people's courage, no "escape" game mechanics.
 */
val NorthStarRoute = Route(
    id = "north-star-1",
    title = "The North Star",
    subtitle = "Chapter 1 · Dorchester County to Philadelphia",
    milestones = listOf(
        Milestone(
            "Bucktown, Maryland", LatLng(38.4300, -76.0600),
            "Harriet Tubman was born Araminta Ross into slavery in Dorchester County around 1822. " +
                "She worked these fields and forests as a child, learning the land she would later cross in the dark.",
        ),
        Milestone(
            "Cambridge, Maryland", LatLng(38.5632, -76.0788),
            "Cambridge, on the Choptank River, was the county seat, where enslaved people were bought and sold. " +
                "Fear of being sold away from family drove many to risk everything to go north.",
        ),
        Milestone(
            "Poplar Neck, Caroline County", LatLng(38.7470, -75.8700),
            "In the fall of 1849 Tubman left from near here, travelling at night and guided by the North Star. " +
                "She would return about thirteen times to lead roughly seventy family members and friends to freedom.",
        ),
        Milestone(
            "Along the Choptank", LatLng(38.8800, -75.8100),
            "Rivers and creeks were roads for freedom seekers: water hid tracks, and following it north kept them on course.",
        ),
        Milestone(
            "Camden, Delaware", LatLng(39.1134, -75.5419),
            "Delaware was a slave state, but Quaker communities like Camden's included people who sheltered and guided freedom seekers.",
        ),
        Milestone(
            "Dover, Delaware", LatLng(39.1582, -75.5244),
            "Slave catchers watched the roads through Dover. In 1857 the 'Dover Eight', guided by Tubman's network, " +
                "fought their way out of the town jail where they'd been betrayed, and continued north.",
        ),
        Milestone(
            "Odessa, Delaware", LatLng(39.4576, -75.6566),
            "By local tradition, the Appoquinimink Friends Meeting House here hid freedom seekers in its loft.",
        ),
        Milestone(
            "New Castle, Delaware", LatLng(39.6620, -75.5663),
            "In 1848 Quaker abolitionists Thomas Garrett and John Hunn were tried here and fined so heavily for aiding " +
                "freedom seekers that it took most of what they owned. Garrett told the court he would keep helping anyway.",
        ),
        Milestone(
            "Wilmington, Delaware", LatLng(39.7391, -75.5398),
            "Thomas Garrett's home was one of the last stops before free soil. He is credited with helping over 2,500 people, " +
                "Tubman among them many times.",
        ),
        Milestone(
            "The Pennsylvania line", LatLng(39.8100, -75.4500),
            "Crossing into Pennsylvania meant entering a free state. But after the Fugitive Slave Act of 1850, " +
                "no Northern state was truly safe, and many kept going to Canada.",
        ),
        Milestone(
            "Chester, Pennsylvania", LatLng(39.8496, -75.3557),
            "Black and white abolitionists in Chester and Delaware County passed freedom seekers on toward Philadelphia.",
        ),
        Milestone(
            "Philadelphia, Pennsylvania", LatLng(39.9526, -75.1652),
            "William Still of the Philadelphia Vigilance Committee interviewed hundreds of freedom seekers and wrote down their stories, " +
                "so they wouldn't be forgotten. Tubman lived and worked here after 1849. Chapter 1 complete.",
        ),
    ),
)
