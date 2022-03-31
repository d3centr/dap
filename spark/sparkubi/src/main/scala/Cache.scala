package fyi.dap.sparkubi

import Typecast.{BD, BD2}

object Cache {

    val BitFractions = Map(
        -192 -> BD2.pow(-192), 
        0    -> BD("1"), 
        192  -> BD2.pow(192))

    /* Steps to create or update ScalePowers cache code
        1) analyse scale distribution in profiling logs, e.g. 
            SELECT min(scale), max(scale) FROM scale2
        2) generate hardcoded cache in shell from defined range:
            println((-80 to 147).map(scale => (scale, 
                s"""BD("${BD10.pow(-scale)}")""")).toString.replace(" ","\n"))
        3) turn the resulting Vector into a Map to keep ordered powers in source
    */
    val ScalePowers =
        Vector((-80,BD("100000000000000000000000000000000000000000000000000000000000000000000000000000000")),
        (-79,BD("10000000000000000000000000000000000000000000000000000000000000000000000000000000")),
        (-78,BD("1000000000000000000000000000000000000000000000000000000000000000000000000000000")),
        (-77,BD("100000000000000000000000000000000000000000000000000000000000000000000000000000")),
        (-76,BD("10000000000000000000000000000000000000000000000000000000000000000000000000000")),
        (-75,BD("1000000000000000000000000000000000000000000000000000000000000000000000000000")),
        (-74,BD("100000000000000000000000000000000000000000000000000000000000000000000000000")),
        (-73,BD("10000000000000000000000000000000000000000000000000000000000000000000000000")),
        (-72,BD("1000000000000000000000000000000000000000000000000000000000000000000000000")),
        (-71,BD("100000000000000000000000000000000000000000000000000000000000000000000000")),
        (-70,BD("10000000000000000000000000000000000000000000000000000000000000000000000")),
        (-69,BD("1000000000000000000000000000000000000000000000000000000000000000000000")),
        (-68,BD("100000000000000000000000000000000000000000000000000000000000000000000")),
        (-67,BD("10000000000000000000000000000000000000000000000000000000000000000000")),
        (-66,BD("1000000000000000000000000000000000000000000000000000000000000000000")),
        (-65,BD("100000000000000000000000000000000000000000000000000000000000000000")),
        (-64,BD("10000000000000000000000000000000000000000000000000000000000000000")),
        (-63,BD("1000000000000000000000000000000000000000000000000000000000000000")),
        (-62,BD("100000000000000000000000000000000000000000000000000000000000000")),
        (-61,BD("10000000000000000000000000000000000000000000000000000000000000")),
        (-60,BD("1000000000000000000000000000000000000000000000000000000000000")),
        (-59,BD("100000000000000000000000000000000000000000000000000000000000")),
        (-58,BD("10000000000000000000000000000000000000000000000000000000000")),
        (-57,BD("1000000000000000000000000000000000000000000000000000000000")),
        (-56,BD("100000000000000000000000000000000000000000000000000000000")),
        (-55,BD("10000000000000000000000000000000000000000000000000000000")),
        (-54,BD("1000000000000000000000000000000000000000000000000000000")),
        (-53,BD("100000000000000000000000000000000000000000000000000000")),
        (-52,BD("10000000000000000000000000000000000000000000000000000")),
        (-51,BD("1000000000000000000000000000000000000000000000000000")),
        (-50,BD("100000000000000000000000000000000000000000000000000")),
        (-49,BD("10000000000000000000000000000000000000000000000000")),
        (-48,BD("1000000000000000000000000000000000000000000000000")),
        (-47,BD("100000000000000000000000000000000000000000000000")),
        (-46,BD("10000000000000000000000000000000000000000000000")),
        (-45,BD("1000000000000000000000000000000000000000000000")),
        (-44,BD("100000000000000000000000000000000000000000000")),
        (-43,BD("10000000000000000000000000000000000000000000")),
        (-42,BD("1000000000000000000000000000000000000000000")),
        (-41,BD("100000000000000000000000000000000000000000")),
        (-40,BD("10000000000000000000000000000000000000000")),
        (-39,BD("1000000000000000000000000000000000000000")),
        (-38,BD("100000000000000000000000000000000000000")),
        (-37,BD("10000000000000000000000000000000000000")),
        (-36,BD("1000000000000000000000000000000000000")),
        (-35,BD("100000000000000000000000000000000000")),
        (-34,BD("10000000000000000000000000000000000")),
        (-33,BD("1000000000000000000000000000000000")),
        (-32,BD("100000000000000000000000000000000")),
        (-31,BD("10000000000000000000000000000000")),
        (-30,BD("1000000000000000000000000000000")),
        (-29,BD("100000000000000000000000000000")),
        (-28,BD("10000000000000000000000000000")),
        (-27,BD("1000000000000000000000000000")),
        (-26,BD("100000000000000000000000000")),
        (-25,BD("10000000000000000000000000")),
        (-24,BD("1000000000000000000000000")),
        (-23,BD("100000000000000000000000")),
        (-22,BD("10000000000000000000000")),
        (-21,BD("1000000000000000000000")),
        (-20,BD("100000000000000000000")),
        (-19,BD("10000000000000000000")),
        (-18,BD("1000000000000000000")),
        (-17,BD("100000000000000000")),
        (-16,BD("10000000000000000")),
        (-15,BD("1000000000000000")),
        (-14,BD("100000000000000")),
        (-13,BD("10000000000000")),
        (-12,BD("1000000000000")),
        (-11,BD("100000000000")),
        (-10,BD("10000000000")),
        (-9,BD("1000000000")),
        (-8,BD("100000000")),
        (-7,BD("10000000")),
        (-6,BD("1000000")),
        (-5,BD("100000")),
        (-4,BD("10000")),
        (-3,BD("1000")),
        (-2,BD("100")),
        (-1,BD("10")),
        (0,BD("1")),
        (1,BD("0.1")),
        (2,BD("0.01")),
        (3,BD("0.001")),
        (4,BD("0.0001")),
        (5,BD("0.00001")),
        (6,BD("0.000001")),
        (7,BD("1E-7")),
        (8,BD("1E-8")),
        (9,BD("1E-9")),
        (10,BD("1E-10")),
        (11,BD("1E-11")),
        (12,BD("1E-12")),
        (13,BD("1E-13")),
        (14,BD("1E-14")),
        (15,BD("1E-15")),
        (16,BD("1E-16")),
        (17,BD("1E-17")),
        (18,BD("1E-18")),
        (19,BD("1E-19")),
        (20,BD("1E-20")),
        (21,BD("1E-21")),
        (22,BD("1E-22")),
        (23,BD("1E-23")),
        (24,BD("1E-24")),
        (25,BD("1E-25")),
        (26,BD("1E-26")),
        (27,BD("1E-27")),
        (28,BD("1E-28")),
        (29,BD("1E-29")),
        (30,BD("1E-30")),
        (31,BD("1E-31")),
        (32,BD("1E-32")),
        (33,BD("1E-33")),
        (34,BD("1E-34")),
        (35,BD("1E-35")),
        (36,BD("1E-36")),
        (37,BD("1E-37")),
        (38,BD("1E-38")),
        (39,BD("1E-39")),
        (40,BD("1E-40")),
        (41,BD("1E-41")),
        (42,BD("1E-42")),
        (43,BD("1E-43")),
        (44,BD("1E-44")),
        (45,BD("1E-45")),
        (46,BD("1E-46")),
        (47,BD("1E-47")),
        (48,BD("1E-48")),
        (49,BD("1E-49")),
        (50,BD("1E-50")),
        (51,BD("1E-51")),
        (52,BD("1E-52")),
        (53,BD("1E-53")),
        (54,BD("1E-54")),
        (55,BD("1E-55")),
        (56,BD("1E-56")),
        (57,BD("1E-57")),
        (58,BD("1E-58")),
        (59,BD("1E-59")),
        (60,BD("1E-60")),
        (61,BD("1E-61")),
        (62,BD("1E-62")),
        (63,BD("1E-63")),
        (64,BD("1E-64")),
        (65,BD("1E-65")),
        (66,BD("1E-66")),
        (67,BD("1E-67")),
        (68,BD("1E-68")),
        (69,BD("1E-69")),
        (70,BD("1E-70")),
        (71,BD("1E-71")),
        (72,BD("1E-72")),
        (73,BD("1E-73")),
        (74,BD("1E-74")),
        (75,BD("1E-75")),
        (76,BD("1E-76")),
        (77,BD("1E-77")),
        (78,BD("1E-78")),
        (79,BD("1E-79")),
        (80,BD("1E-80")),
        (81,BD("1E-81")),
        (82,BD("1E-82")),
        (83,BD("1E-83")),
        (84,BD("1E-84")),
        (85,BD("1E-85")),
        (86,BD("1E-86")),
        (87,BD("1E-87")),
        (88,BD("1E-88")),
        (89,BD("1E-89")),
        (90,BD("1E-90")),
        (91,BD("1E-91")),
        (92,BD("1E-92")),
        (93,BD("1E-93")),
        (94,BD("1E-94")),
        (95,BD("1E-95")),
        (96,BD("1E-96")),
        (97,BD("1E-97")),
        (98,BD("1E-98")),
        (99,BD("1E-99")),
        (100,BD("1E-100")),
        (101,BD("1E-101")),
        (102,BD("1E-102")),
        (103,BD("1E-103")),
        (104,BD("1E-104")),
        (105,BD("1E-105")),
        (106,BD("1E-106")),
        (107,BD("1E-107")),
        (108,BD("1E-108")),
        (109,BD("1E-109")),
        (110,BD("1E-110")),
        (111,BD("1E-111")),
        (112,BD("1E-112")),
        (113,BD("1E-113")),
        (114,BD("1E-114")),
        (115,BD("1E-115")),
        (116,BD("1E-116")),
        (117,BD("1E-117")),
        (118,BD("1E-118")),
        (119,BD("1E-119")),
        (120,BD("1E-120")),
        (121,BD("1E-121")),
        (122,BD("1E-122")),
        (123,BD("1E-123")),
        (124,BD("1E-124")),
        (125,BD("1E-125")),
        (126,BD("1E-126")),
        (127,BD("1E-127")),
        (128,BD("1E-128")),
        (129,BD("1E-129")),
        (130,BD("1E-130")),
        (131,BD("1E-131")),
        (132,BD("1E-132")),
        (133,BD("1E-133")),
        (134,BD("1E-134")),
        (135,BD("1E-135")),
        (136,BD("1E-136")),
        (137,BD("1E-137")),
        (138,BD("1E-138")),
        (139,BD("1E-139")),
        (140,BD("1E-140")),
        (141,BD("1E-141")),
        (142,BD("1E-142")),
        (143,BD("1E-143")),
        (144,BD("1E-144")),
        (145,BD("1E-145")),
        (146,BD("1E-146")),
        (147,BD("1E-147"))).toMap

}

