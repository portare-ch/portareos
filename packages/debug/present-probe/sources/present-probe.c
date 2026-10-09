// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026-present PortareOS (https://github.com/portare-ch)
//
// present-probe: a Vulkan client of the KHR display path that presents a
// known schedule, so what a presentation layer or the panel did with it can
// be checked frame by frame (issue #595).
//
// Schedules: "cadence:2,2,4" holds frames for that many refreshes in turn on
// a fixed refresh; "rate:59.826" aims frames at a fixed rate, for a variable
// refresh panel (MESA_VK_WSI_DISPLAY_VRR=1); "rate:30,60" steps through the
// rates in one session, switch=S seconds each, in turn.
//
// Modes:
//   own      no VK_GOOGLE_display_timing. Cadence only: each frame is
//            presented right after the vblank before the one it should
//            start on, counted with VK_EXT_display_control vblank events.
//            A layer that times presents itself (MangoHud) reads the records.
//   observe  every present carries a VK_GOOGLE_display_timing target and an
//            ID, and the probe reads the records itself after each present.
//   partial  observe, with every tenth present untagged.
//
// Options:
//   read=N      read records with an array of N (default 64); "count" asks
//               for the count first and reads that many; "none" never reads
//   late=E:MS   every Eth frame is presented MS ms after its target (rate);
//               in cadence mode it is held one refresh more
//   mode=HZ     the display mode nearest HZ (default: the fastest)
//   recreate=S  replace the swapchain every S seconds (oldSwapchain)
//   switch=S    with several rates, how long each lasts (default 5)
//
// Every frame draws its number as a barcode, so each frame's pixels, and the
// DPU's CRC of them, differ from the last.
//
// Output: OUT.presents.csv, one line per present (id, image, whether it was
// tagged, its target, when it was presented, whether it was scripted late),
// and OUT.records.csv, one line per record read, or per read that returned
// none (read, asked, got, result, then the record's fields). Times are
// CLOCK_MONOTONIC in ns.
//
// usage: present-probe OUT SECONDS own|observe|partial cadence:N,N,..|rate:HZ[,HZ..] [read=..] [late=E:MS] [mode=HZ] [recreate=S] [switch=S]

#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>

#define MAX_CADENCE 16
#define MAX_IMAGES 8
#define BLOCK 24
#define BITS 24

enum mode { MODE_OWN, MODE_OBSERVE, MODE_PARTIAL };

struct present_rec {
	uint32_t id, image;
	uint8_t tagged, late;
	uint64_t target, call;
};

struct timing_rec {
	uint32_t read, asked, got;
	int32_t result;
	uint8_t has;
	VkPastPresentationTimingGOOGLE t;
};

static volatile sig_atomic_t stop;

static struct present_rec *presents;
static size_t npresents, maxpresents;
static struct timing_rec *timings;
static size_t ntimings, maxtimings;

static VkInstance instance;
static VkPhysicalDevice pdev;
static VkDevice device;
static VkQueue queue;
static VkDisplayKHR display;
static VkSurfaceKHR surface;
static VkSwapchainKHR swapchain;
static VkImage images[MAX_IMAGES];
static uint32_t nimages;
static VkExtent2D extent;
static VkCommandPool pool;
static VkCommandBuffer cmds[MAX_IMAGES];
static VkFence fences[MAX_IMAGES];
static VkSemaphore acquired[MAX_IMAGES + 1], rendered[MAX_IMAGES];
static VkBuffer staging;
static VkDeviceMemory staging_mem;

static PFN_vkGetPastPresentationTimingGOOGLE get_past_timing;
static PFN_vkRegisterDisplayEventEXT register_display_event;

static void on_signal(int s) { (void)s; stop = 1; }

static uint64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void sleep_until(uint64_t t)
{
	struct timespec ts = { .tv_sec = t / 1000000000ull, .tv_nsec = t % 1000000000ull };
	while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL) == EINTR && !stop)
		;
}

static void die(const char *what, VkResult r)
{
	fprintf(stderr, "present-probe: %s: %d\n", what, r);
	exit(1);
}

#define VK(call) do { VkResult r_ = (call); if (r_ != VK_SUCCESS) die(#call, r_); } while (0)

static void *grow(void *p, size_t *max, size_t size)
{
	*max = *max ? *max * 2 : 4096;
	p = realloc(p, *max * size);
	if (!p) {
		fprintf(stderr, "present-probe: out of memory\n");
		exit(1);
	}
	return p;
}

static int has_extension(const VkExtensionProperties *ext, uint32_t n, const char *name)
{
	for (uint32_t i = 0; i < n; i++)
		if (!strcmp(ext[i].extensionName, name))
			return 1;
	return 0;
}

static uint32_t memory_type(uint32_t bits, VkMemoryPropertyFlags want)
{
	VkPhysicalDeviceMemoryProperties mp;
	vkGetPhysicalDeviceMemoryProperties(pdev, &mp);
	for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
		if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & want) == want)
			return i;
	die("no host-visible memory", VK_ERROR_UNKNOWN);
	return 0;
}

// The fastest mode, or the one nearest mode_mhz.
static VkDisplayModePropertiesKHR pick_mode(uint32_t mode_mhz)
{
	uint32_t n = 0;
	VK(vkGetDisplayModePropertiesKHR(pdev, display, &n, NULL));
	VkDisplayModePropertiesKHR *modes = calloc(n, sizeof(*modes));
	VK(vkGetDisplayModePropertiesKHR(pdev, display, &n, modes));
	VkDisplayModePropertiesKHR best = modes[0];
	for (uint32_t i = 1; i < n; i++) {
		uint32_t r = modes[i].parameters.refreshRate, b = best.parameters.refreshRate;
		if (mode_mhz ? abs((int)r - (int)mode_mhz) < abs((int)b - (int)mode_mhz) : r > b)
			best = modes[i];
	}
	free(modes);
	return best;
}

static void create_surface(uint32_t mode_mhz, uint64_t *refresh_ns)
{
	uint32_t n = 1;
	VkDisplayPropertiesKHR dp;
	VkResult r = vkGetPhysicalDeviceDisplayPropertiesKHR(pdev, &n, &dp);
	if ((r != VK_SUCCESS && r != VK_INCOMPLETE) || !n)
		die("no display", r);
	display = dp.display;

	VkDisplayModePropertiesKHR mode = pick_mode(mode_mhz);
	*refresh_ns = 1000000000000ull / mode.parameters.refreshRate;

	uint32_t nplanes = 0, plane = UINT32_MAX;
	VK(vkGetPhysicalDeviceDisplayPlanePropertiesKHR(pdev, &nplanes, NULL));
	VkDisplayPlanePropertiesKHR *planes = calloc(nplanes, sizeof(*planes));
	VK(vkGetPhysicalDeviceDisplayPlanePropertiesKHR(pdev, &nplanes, planes));
	for (uint32_t i = 0; i < nplanes && plane == UINT32_MAX; i++) {
		uint32_t nd = 0;
		VK(vkGetDisplayPlaneSupportedDisplaysKHR(pdev, i, &nd, NULL));
		VkDisplayKHR *ds = calloc(nd, sizeof(*ds));
		VK(vkGetDisplayPlaneSupportedDisplaysKHR(pdev, i, &nd, ds));
		for (uint32_t j = 0; j < nd; j++)
			if (ds[j] == display)
				plane = i;
		free(ds);
	}
	if (plane == UINT32_MAX)
		die("no plane for the display", VK_ERROR_UNKNOWN);

	extent = mode.parameters.visibleRegion;
	VkDisplaySurfaceCreateInfoKHR ci = {
		.sType = VK_STRUCTURE_TYPE_DISPLAY_SURFACE_CREATE_INFO_KHR,
		.displayMode = mode.displayMode,
		.planeIndex = plane,
		.planeStackIndex = planes[plane].currentStackIndex,
		.transform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
		.globalAlpha = 1.0f,
		.alphaMode = VK_DISPLAY_PLANE_ALPHA_OPAQUE_BIT_KHR,
		.imageExtent = extent,
	};
	free(planes);
	VK(vkCreateDisplayPlaneSurfaceKHR(instance, &ci, NULL, &surface));
	fprintf(stderr, "present-probe: %ux%u at %.3f Hz, plane %u\n", extent.width, extent.height,
		mode.parameters.refreshRate / 1000.0, plane);
}

static void create_device(enum mode mode)
{
	uint32_t nq = 0, family = UINT32_MAX;
	vkGetPhysicalDeviceQueueFamilyProperties(pdev, &nq, NULL);
	VkQueueFamilyProperties *qf = calloc(nq, sizeof(*qf));
	vkGetPhysicalDeviceQueueFamilyProperties(pdev, &nq, qf);
	for (uint32_t i = 0; i < nq && family == UINT32_MAX; i++) {
		VkBool32 ok = VK_FALSE;
		vkGetPhysicalDeviceSurfaceSupportKHR(pdev, i, surface, &ok);
		if (ok && (qf[i].queueFlags & VK_QUEUE_GRAPHICS_BIT))
			family = i;
	}
	free(qf);
	if (family == UINT32_MAX)
		die("no queue that can present", VK_ERROR_UNKNOWN);

	uint32_t next = 0;
	VK(vkEnumerateDeviceExtensionProperties(pdev, NULL, &next, NULL));
	VkExtensionProperties *ext = calloc(next, sizeof(*ext));
	VK(vkEnumerateDeviceExtensionProperties(pdev, NULL, &next, ext));
	const char *want[2] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
	if (mode == MODE_OWN)
		want[1] = VK_EXT_DISPLAY_CONTROL_EXTENSION_NAME;
	else
		want[1] = VK_GOOGLE_DISPLAY_TIMING_EXTENSION_NAME;
	if (!has_extension(ext, next, want[1]))
		die(want[1], VK_ERROR_EXTENSION_NOT_PRESENT);
	free(ext);

	float prio = 1.0f;
	VkDeviceQueueCreateInfo qci = {
		.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
		.queueFamilyIndex = family,
		.queueCount = 1,
		.pQueuePriorities = &prio,
	};
	VkDeviceCreateInfo dci = {
		.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.queueCreateInfoCount = 1,
		.pQueueCreateInfos = &qci,
		.enabledExtensionCount = 2,
		.ppEnabledExtensionNames = want,
	};
	VK(vkCreateDevice(pdev, &dci, NULL, &device));
	vkGetDeviceQueue(device, family, 0, &queue);

	if (mode == MODE_OWN)
		register_display_event = (PFN_vkRegisterDisplayEventEXT)
			vkGetDeviceProcAddr(device, "vkRegisterDisplayEventEXT");
	else
		get_past_timing = (PFN_vkGetPastPresentationTimingGOOGLE)
			vkGetDeviceProcAddr(device, "vkGetPastPresentationTimingGOOGLE");
	if (mode == MODE_OWN ? !register_display_event : !get_past_timing)
		die("entry point missing", VK_ERROR_EXTENSION_NOT_PRESENT);

	VkCommandPoolCreateInfo pci = {
		.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
		.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
		.queueFamilyIndex = family,
	};
	VK(vkCreateCommandPool(device, &pci, NULL, &pool));
}

static void create_swapchain(VkSwapchainKHR old)
{
	VkSurfaceCapabilitiesKHR caps;
	VK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pdev, surface, &caps));
	if (!(caps.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT))
		die("swapchain images cannot be a transfer target", VK_ERROR_FEATURE_NOT_PRESENT);

	uint32_t nf = 0;
	VK(vkGetPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &nf, NULL));
	VkSurfaceFormatKHR *formats = calloc(nf, sizeof(*formats));
	VK(vkGetPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &nf, formats));
	VkSurfaceFormatKHR format = formats[0];
	for (uint32_t i = 0; i < nf; i++)
		if (formats[i].format == VK_FORMAT_B8G8R8A8_UNORM)
			format = formats[i];
	free(formats);

	// Two images, as RetroArch runs on the Nova.
	uint32_t count = caps.minImageCount > 2 ? caps.minImageCount : 2;
	VkSwapchainCreateInfoKHR ci = {
		.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
		.surface = surface,
		.minImageCount = count,
		.imageFormat = format.format,
		.imageColorSpace = format.colorSpace,
		.imageExtent = extent,
		.imageArrayLayers = 1,
		.imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT,
		.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
		.preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
		.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
		.presentMode = VK_PRESENT_MODE_FIFO_KHR,
		.clipped = VK_TRUE,
		.oldSwapchain = old,
	};
	VK(vkCreateSwapchainKHR(device, &ci, NULL, &swapchain));
	if (old)
		vkDestroySwapchainKHR(device, old, NULL);
	nimages = MAX_IMAGES;
	VK(vkGetSwapchainImagesKHR(device, swapchain, &nimages, images));

	VkCommandBufferAllocateInfo ai = {
		.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
		.commandPool = pool,
		.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
		.commandBufferCount = nimages,
	};
	VK(vkAllocateCommandBuffers(device, &ai, cmds));
	VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT };
	VkSemaphoreCreateInfo sci = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
	for (uint32_t i = 0; i < nimages; i++) {
		VK(vkCreateFence(device, &fci, NULL, &fences[i]));
		VK(vkCreateSemaphore(device, &sci, NULL, &rendered[i]));
	}
	for (uint32_t i = 0; i <= nimages; i++)
		VK(vkCreateSemaphore(device, &sci, NULL, &acquired[i]));
}

static void destroy_swapchain_objects(void)
{
	vkFreeCommandBuffers(device, pool, nimages, cmds);
	for (uint32_t i = 0; i < nimages; i++) {
		vkDestroyFence(device, fences[i], NULL);
		vkDestroySemaphore(device, rendered[i], NULL);
	}
	for (uint32_t i = 0; i <= nimages; i++)
		vkDestroySemaphore(device, acquired[i], NULL);
}

// A swapchain in place of the current one, as a resize would make.
static void recreate_swapchain(void)
{
	VK(vkDeviceWaitIdle(device));
	destroy_swapchain_objects();
	create_swapchain(swapchain);
}

static void create_staging(void)
{
	// A white block and a black one, copied into place for each bit.
	VkBufferCreateInfo bci = {
		.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
		.size = 2 * BLOCK * BLOCK * 4,
		.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
	};
	VK(vkCreateBuffer(device, &bci, NULL, &staging));
	VkMemoryRequirements mr;
	vkGetBufferMemoryRequirements(device, staging, &mr);
	VkMemoryAllocateInfo mai = {
		.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
		.allocationSize = mr.size,
		.memoryTypeIndex = memory_type(mr.memoryTypeBits,
			VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
	};
	VK(vkAllocateMemory(device, &mai, NULL, &staging_mem));
	VK(vkBindBufferMemory(device, staging, staging_mem, 0));
	uint32_t *px;
	VK(vkMapMemory(device, staging_mem, 0, bci.size, 0, (void **)&px));
	for (int i = 0; i < BLOCK * BLOCK; i++) {
		px[i] = 0xffffffff;
		px[BLOCK * BLOCK + i] = 0xff000000;
	}
	vkUnmapMemory(device, staging_mem);
}

static void barrier(VkCommandBuffer cb, VkImage img, VkImageLayout from, VkImageLayout to,
		    VkAccessFlags src_access, VkAccessFlags dst_access,
		    VkPipelineStageFlags src, VkPipelineStageFlags dst)
{
	VkImageMemoryBarrier b = {
		.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
		.srcAccessMask = src_access,
		.dstAccessMask = dst_access,
		.oldLayout = from,
		.newLayout = to,
		.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
		.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
		.image = img,
		.subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 },
	};
	vkCmdPipelineBarrier(cb, src, dst, 0, 0, NULL, 0, NULL, 1, &b);
}

// Acquire the next image and render frame `frame` into it. Returns the image.
static uint32_t render(uint32_t frame, uint32_t slot)
{
	uint32_t img;
	VkResult r = vkAcquireNextImageKHR(device, swapchain, UINT64_MAX, acquired[slot], VK_NULL_HANDLE, &img);
	if (r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR)
		die("vkAcquireNextImageKHR", r);

	VK(vkWaitForFences(device, 1, &fences[img], VK_TRUE, UINT64_MAX));
	VK(vkResetFences(device, 1, &fences[img]));
	VkCommandBuffer cb = cmds[img];
	VK(vkResetCommandBuffer(cb, 0));
	VkCommandBufferBeginInfo bi = {
		.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
		.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
	};
	VK(vkBeginCommandBuffer(cb, &bi));
	barrier(cb, images[img], VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
		0, VK_ACCESS_TRANSFER_WRITE_BIT,
		VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
	VkClearColorValue grey = { .float32 = { 0.1f, 0.1f, 0.1f, 1.0f } };
	VkImageSubresourceRange all = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
	vkCmdClearColorImage(cb, images[img], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &grey, 1, &all);
	barrier(cb, images[img], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
		VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
		VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
	VkBufferImageCopy regions[BITS];
	for (int b = 0; b < BITS; b++) {
		regions[b] = (VkBufferImageCopy){
			.bufferOffset = (frame >> b & 1) ? 0 : BLOCK * BLOCK * 4,
			.imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 },
			.imageOffset = { (int32_t)(BLOCK + b * (BLOCK + BLOCK / 2)), BLOCK, 0 },
			.imageExtent = { BLOCK, BLOCK, 1 },
		};
	}
	vkCmdCopyBufferToImage(cb, staging, images[img], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, BITS, regions);
	barrier(cb, images[img], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
		VK_ACCESS_TRANSFER_WRITE_BIT, 0,
		VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT);
	VK(vkEndCommandBuffer(cb));

	VkPipelineStageFlags stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
	VkSubmitInfo si = {
		.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
		.waitSemaphoreCount = 1,
		.pWaitSemaphores = &acquired[slot],
		.pWaitDstStageMask = &stage,
		.commandBufferCount = 1,
		.pCommandBuffers = &cb,
		.signalSemaphoreCount = 1,
		.pSignalSemaphores = &rendered[img],
	};
	VK(vkQueueSubmit(queue, 1, &si, fences[img]));
	return img;
}

static void present(uint32_t img, uint32_t id, int tagged, uint64_t target, int late)
{
	VkPresentTimeGOOGLE t = { .presentID = id, .desiredPresentTime = target };
	VkPresentTimesInfoGOOGLE times = {
		.sType = VK_STRUCTURE_TYPE_PRESENT_TIMES_INFO_GOOGLE,
		.swapchainCount = 1,
		.pTimes = &t,
	};
	VkPresentInfoKHR pi = {
		.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
		.pNext = tagged ? &times : NULL,
		.waitSemaphoreCount = 1,
		.pWaitSemaphores = &rendered[img],
		.swapchainCount = 1,
		.pSwapchains = &swapchain,
		.pImageIndices = &img,
	};
	if (npresents == maxpresents)
		presents = grow(presents, &maxpresents, sizeof(*presents));
	presents[npresents++] = (struct present_rec){
		.id = id, .image = img, .tagged = tagged, .late = late, .target = target, .call = now_ns(),
	};
	VkResult r = vkQueuePresentKHR(queue, &pi);
	if (r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR)
		die("vkQueuePresentKHR", r);
}

static void add_timing(uint32_t read, uint32_t asked, uint32_t got, VkResult result,
		       const VkPastPresentationTimingGOOGLE *t)
{
	if (ntimings == maxtimings)
		timings = grow(timings, &maxtimings, sizeof(*timings));
	timings[ntimings++] = (struct timing_rec){
		.read = read, .asked = asked, .got = got, .result = result,
		.has = t != NULL, .t = t ? *t : (VkPastPresentationTimingGOOGLE){ 0 },
	};
}

// One read as the options say; returns the newest record's actual time and
// sets *newest_id, or returns 0 when it brought none.
static uint64_t read_timings(int read_mode, uint32_t *newest_id)
{
	static uint32_t reads;
	static VkPastPresentationTimingGOOGLE buf[256];
	uint32_t asked = read_mode, got;
	VkResult r;
	uint64_t newest = 0;

	if (read_mode < 0)
		return 0;
	reads++;
	if (read_mode == 0) {
		r = get_past_timing(device, swapchain, &got, NULL);
		add_timing(reads, 0, got, r, NULL);
		asked = got < 256 ? got : 256;
		if (!asked)
			return 0;
	}
	got = asked;
	r = get_past_timing(device, swapchain, &got, buf);
	if (!got)
		add_timing(reads, asked, 0, r, NULL);
	for (uint32_t i = 0; i < got; i++) {
		add_timing(reads, asked, got, r, &buf[i]);
		if (buf[i].actualPresentTime > newest) {
			newest = buf[i].actualPresentTime;
			*newest_id = buf[i].presentID;
		}
	}
	return newest;
}

static uint64_t first_frame_on_screen(int read_mode)
{
	uint64_t deadline = now_ns() + 2000000000ull;
	uint32_t id = 0;

	if (read_mode < 0) {
		sleep_until(now_ns() + 1000000000ull);
		return now_ns();
	}
	while (now_ns() < deadline && !stop) {
		uint64_t t = read_timings(read_mode, &id);
		if (t)
			return t;
		sleep_until(now_ns() + 2000000ull);
	}
	return now_ns();
}

static void wait_vblank(void)
{
	VkDisplayEventInfoEXT ei = {
		.sType = VK_STRUCTURE_TYPE_DISPLAY_EVENT_INFO_EXT,
		.displayEvent = VK_DISPLAY_EVENT_TYPE_FIRST_PIXEL_OUT_EXT,
	};
	VkFence f;
	VK(register_display_event(device, display, &ei, NULL, &f));
	VK(vkWaitForFences(device, 1, &f, VK_TRUE, 1000000000ull));
	vkDestroyFence(device, f, NULL);
}

static void write_logs(const char *out)
{
	char path[512];
	snprintf(path, sizeof(path), "%s.presents.csv", out);
	FILE *f = fopen(path, "w");
	if (!f) {
		perror(path);
		return;
	}
	fprintf(f, "id,image,tagged,target_ns,call_ns,late\n");
	for (size_t i = 0; i < npresents; i++)
		fprintf(f, "%u,%u,%u,%llu,%llu,%u\n", presents[i].id, presents[i].image, presents[i].tagged,
			(unsigned long long)presents[i].target, (unsigned long long)presents[i].call,
			presents[i].late);
	fclose(f);

	snprintf(path, sizeof(path), "%s.records.csv", out);
	f = fopen(path, "w");
	if (!f) {
		perror(path);
		return;
	}
	fprintf(f, "read,asked,got,result,present_id,desired_ns,actual_ns,earliest_ns,margin_ns\n");
	for (size_t i = 0; i < ntimings; i++) {
		struct timing_rec *t = &timings[i];
		fprintf(f, "%u,%u,%u,%d", t->read, t->asked, t->got, t->result);
		if (t->has)
			fprintf(f, ",%u,%llu,%llu,%llu,%llu\n", t->t.presentID,
				(unsigned long long)t->t.desiredPresentTime,
				(unsigned long long)t->t.actualPresentTime,
				(unsigned long long)t->t.earliestPresentTime,
				(unsigned long long)t->t.presentMargin);
		else
			fprintf(f, ",,,,,\n");
	}
	fclose(f);
}

int main(int argc, char **argv)
{
	if (argc < 5) {
		fprintf(stderr, "usage: present-probe OUT SECONDS own|observe|partial cadence:N,N,..|rate:HZ[,HZ..]"
			" [read=N|count|none] [late=E:MS] [mode=HZ] [recreate=S] [switch=S]\n");
		return 2;
	}
	const char *out = argv[1];
	double seconds = atof(argv[2]);
	enum mode mode = !strcmp(argv[3], "own") ? MODE_OWN :
			 !strcmp(argv[3], "observe") ? MODE_OBSERVE :
			 !strcmp(argv[3], "partial") ? MODE_PARTIAL : -1;
	unsigned cadence[MAX_CADENCE], ncadence = 0;
	double rates[MAX_CADENCE], rate = 0;
	unsigned nrates = 0;
	double switch_s = 5;
	int read_mode = 64;
	unsigned late_every = 0;
	double late_ms = 0;
	uint32_t mode_mhz = 0;
	double recreate_s = 0;

	if ((int)mode < 0) {
		fprintf(stderr, "present-probe: mode is own, observe or partial\n");
		return 2;
	}
	if (!strncmp(argv[4], "cadence:", 8)) {
		for (char *s = argv[4] + 8; *s && ncadence < MAX_CADENCE; s++) {
			cadence[ncadence++] = strtoul(s, &s, 10);
			if (*s != ',')
				break;
		}
	} else if (!strncmp(argv[4], "rate:", 5)) {
		for (char *s = argv[4] + 5; *s && nrates < MAX_CADENCE; s++) {
			rates[nrates++] = strtod(s, &s);
			if (*s != ',')
				break;
		}
		rate = nrates ? rates[0] : 0;
	}
	if (!ncadence && rate <= 0) {
		fprintf(stderr, "present-probe: schedule is cadence:N,N,.. or rate:HZ\n");
		return 2;
	}
	if (mode == MODE_OWN && !ncadence) {
		fprintf(stderr, "present-probe: own mode holds frames by refreshes; give a cadence\n");
		return 2;
	}
	for (int i = 5; i < argc; i++) {
		if (!strcmp(argv[i], "read=none"))
			read_mode = -1;
		else if (!strcmp(argv[i], "read=count"))
			read_mode = 0;
		else if (!strncmp(argv[i], "read=", 5))
			read_mode = atoi(argv[i] + 5) > 256 ? 256 : atoi(argv[i] + 5);
		else if (!strncmp(argv[i], "late=", 5))
			sscanf(argv[i] + 5, "%u:%lf", &late_every, &late_ms);
		else if (!strncmp(argv[i], "mode=", 5))
			mode_mhz = (uint32_t)(atof(argv[i] + 5) * 1000 + 0.5);
		else if (!strncmp(argv[i], "recreate=", 9))
			recreate_s = atof(argv[i] + 9);
		else if (!strncmp(argv[i], "switch=", 7))
			switch_s = atof(argv[i] + 7);
	}

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	const char *iext[3] = { VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_DISPLAY_EXTENSION_NAME,
				VK_EXT_DISPLAY_SURFACE_COUNTER_EXTENSION_NAME };
	VkApplicationInfo app = {
		.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
		.pApplicationName = "present-probe",
		.apiVersion = VK_API_VERSION_1_1,
	};
	VkInstanceCreateInfo ici = {
		.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
		.pApplicationInfo = &app,
		.enabledExtensionCount = mode == MODE_OWN ? 3 : 2,
		.ppEnabledExtensionNames = iext,
	};
	VK(vkCreateInstance(&ici, NULL, &instance));
	uint32_t npd = 1;
	VkResult r = vkEnumeratePhysicalDevices(instance, &npd, &pdev);
	if ((r != VK_SUCCESS && r != VK_INCOMPLETE) || !npd)
		die("no physical device", r);

	uint64_t refresh;
	create_surface(mode_mhz, &refresh);
	create_device(mode);
	create_swapchain(VK_NULL_HANDLE);
	create_staging();

	uint64_t start = now_ns(), end = start + (uint64_t)(seconds * 1e9);
	uint64_t recreate_ns = (uint64_t)(recreate_s * 1e9), next_recreate = start + recreate_ns;
	uint32_t slot = 0;

	if (mode == MODE_OWN) {
		// Each frame is presented right after the vblank before the one it
		// should start on, and lands on that one. Frame k is held
		// cadence[k] refreshes, one more when scripted late.
		wait_vblank();
		for (uint32_t k = 0; !stop && now_ns() < end; k++) {
			if (recreate_ns && now_ns() >= next_recreate) {
				recreate_swapchain();
				slot = 0;
				next_recreate += recreate_ns;
				wait_vblank();
			}
			uint32_t img = render(k, slot);
			slot = (slot + 1) % (nimages + 1);
			int late = late_every && k % late_every == late_every - 1;
			present(img, k + 1, 0, 0, late);
			unsigned hold = cadence[k % ncadence] + late;
			for (unsigned v = 0; v < hold && !stop; v++)
				wait_vblank();
		}
	} else {
		// Targets: at a fixed rate from the start, or for a cadence half a
		// refresh before the vblank it means, counted from the first
		// record read. A later record moves the anchor only when it shows
		// its frame on the vblank the schedule meant, within a quarter
		// refresh, which follows the panel's clock against CLOCK_MONOTONIC;
		// a late frame, or an untimed one, would start a second schedule
		// beside the first. Each present goes in a few ms before its target.
		uint64_t period = rate > 0 ? (uint64_t)(1e9 / rate) : 0;
		uint64_t switch_ns = (uint64_t)(switch_s * 1e9), t0 = 0, next = 0;
		uint64_t anchor_time = 0, cum = 0;
		uint32_t anchor_id = 0;
		uint64_t *starts = NULL;
		size_t nstarts = 0, maxstarts = 0;

		for (uint32_t k = 0; !stop && now_ns() < end; k++) {
			uint32_t id = k + 1, newest_id = 0;
			if (recreate_ns && now_ns() >= next_recreate) {
				// The old swapchain's records go with it: start over.
				recreate_swapchain();
				slot = 0;
				next_recreate += recreate_ns;
				anchor_time = 0;
			}
			uint32_t img = render(k, slot);
			slot = (slot + 1) % (nimages + 1);
			int late = late_every && k % late_every == late_every - 1;
			int tagged = mode != MODE_PARTIAL || k % 10 != 9;
			uint64_t target = 0;

			if (period) {
				// The first present sets the mode, which takes a few
				// hundred ms: the schedule starts a period after that
				// frame reached the screen, from its record, or a second
				// on when the records are not read.
				if (k == 1)
					t0 = first_frame_on_screen(read_mode) + period;
				if (k == 1 && t0 < now_ns() + 4000000ull)
					t0 = now_ns() + 4000000ull;
				if (k == 1)
					next = t0;
				// Each target a period of the rate its time falls in
				// after the one before, so a switch keeps the content's
				// clock going.
				if (k) {
					unsigned seg = nrates > 1 && switch_ns ?
						(unsigned)((next - t0) / switch_ns % nrates) : 0;
					target = next;
					next += (uint64_t)(1e9 / rates[seg]);
				}
			} else {
				if (nstarts == maxstarts)
					starts = grow(starts, &maxstarts, sizeof(*starts));
				starts[nstarts++] = cum;
				if (anchor_time)
					target = anchor_time + (cum - starts[anchor_id - 1]) * refresh - refresh / 2;
				cum += cadence[k % ncadence] + (late ? 1 : 0);
			}
			if (target > 4000000ull)
				sleep_until(target - 4000000ull);
			if (late && period)
				sleep_until(target + (uint64_t)(late_ms * 1e6));
			present(img, id, tagged, tagged ? target : 0, late);

			uint64_t newest = read_timings(read_mode, &newest_id);
			if (newest && newest_id && newest_id <= nstarts) {
				int64_t off = anchor_time ? (int64_t)(newest - anchor_time) -
					(int64_t)((starts[newest_id - 1] - starts[anchor_id - 1]) * refresh) : 0;
				if (!anchor_time || (presents[newest_id - 1].target &&
						     llabs(off) < (int64_t)refresh / 4)) {
					anchor_time = newest;
					anchor_id = newest_id;
				}
			}
		}
		free(starts);
	}

	vkDeviceWaitIdle(device);
	if (mode != MODE_OWN) {
		uint32_t newest_id;
		read_timings(read_mode, &newest_id);
	}
	write_logs(out);
	fprintf(stderr, "present-probe: %zu presents, %zu record lines\n", npresents, ntimings);

	vkDestroySwapchainKHR(device, swapchain, NULL);
	vkDestroyDevice(device, NULL);
	vkDestroySurfaceKHR(instance, surface, NULL);
	vkDestroyInstance(instance, NULL);
	return 0;
}
